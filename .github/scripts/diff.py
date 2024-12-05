#!/usr/bin/env python3
# Note: only supported python3.11+

import argparse
import dataclasses
import glob
import json
import logging
import os
import re
import subprocess
import sys
from pathlib import Path

logging.basicConfig(
    level=logging.DEBUG if os.environ.get('CI_DEBUG') else logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(lineno)d - %(message)s',
)

logger = logging.getLogger(__name__)

PROJECT_METADATA_FILE_NAME = 'project.json'
CONTAINER_METADATA_FILE_NAME = 'metadata.json'
ENCODING = 'utf-8'

not_regex_pattern = re.compile(r'^[^*?\[\]]*$')


@dataclasses.dataclass
class Container:
    name: str
    version: str
    dependencies: dict[str, str]

    def __repr__(self):
        return f'Container(name={self.name}, version={self.version})'


@dataclasses.dataclass
class ContainerMetadata:
    name: str
    path: Path
    versions: list[Container]

    def __repr__(self) -> str:
        return f'ContainerMetadata(name={self.name})'


@dataclasses.dataclass
class ContainerGroup:
    name: str
    parallel: bool
    containers: list[ContainerMetadata]

    def __repr__(self) -> str:
        return f'ContainerGroup(name={self.name})'


@dataclasses.dataclass
class ProjectMetadata:
    container_roups: list[ContainerGroup]
    global_paths: list[str]


@dataclasses.dataclass
class ChangedContainers:
    groups: dict[str, list[str]]


class SchemaError(Exception):
    pass


class CaculateError(Exception):
    pass


def check_python_version() -> None:
    """
    Check python version, only support python3.11+

    :return: None
    """
    if sys.version_info < (3, 11):
        logger.error(f'Python version should be 3.11+, current version is {sys.version_info}')
        sys.exit(1)


def load_project_metadata(metadata_path: Path = Path(PROJECT_METADATA_FILE_NAME)) -> ProjectMetadata:
    """
    Load project metadata from the metadata.json file in the project directory.


    :param metadata_path: the path of the metadata file

    :return: ProjectMetadata

    """
    with open(metadata_path, 'r', encoding=ENCODING) as f:
        metadata = json.load(f)

    logger.debug(f'loaded project metadata from {metadata_path}: {metadata}')

    glob_paths = metadata.get('global_paths', [])
    path_prefix = Path(metadata.get('path_prefix', ''))
    container_groups: list[ContainerGroup] = []
    for key, container_config in metadata.get('containers', {}).items():
        group_name = key
        parallel = container_config.get('parallel', False)
        containers = []
        for path in container_config.get('paths', []):
            container = load_container_metadata(path_prefix / path)
            containers.append(container)
        container_groups.append(ContainerGroup(name=group_name, parallel=parallel, containers=containers))
    return ProjectMetadata(container_roups=container_groups, global_paths=glob_paths)


def load_container_metadata(path: Path) -> ContainerMetadata:
    """
    Load container metadata from the metadata.json file in the container directory

    :param name: the container name

    :return: ContainerMetadata
    """
    metadata_path = path / CONTAINER_METADATA_FILE_NAME

    with open(metadata_path, 'r', encoding=ENCODING) as f:
        metadata = json.load(f)
    logger.debug(f'loaded container metadata from {metadata_path}: {metadata}')

    # name = metadata['name']
    name = path.name
    versions: str = []
    containers: list[Container] = []
    for property in metadata['properties']:
        version = property['version']
        dependencies = property.get('dependencies', {})
        versions.append(version)
        containers.append(Container(name=name, version=version, dependencies=dependencies))

    logger.debug(f'loaded container metadata: {name}, versions: {versions}')
    return ContainerMetadata(name=name, path=path, versions=containers)


def get_changed_container_name(project_metadata: ProjectMetadata, before_sha: str | None = None, after_sha: str | None = None) -> list[str]:
    """
    Use git diff command to get the changed container between two commits by checking the changed files.

    :param project_metadata: ProjectMetadata
    :param before_sha: the SHA of the commit before the event
    :param after_sha: the SHA of the commit after the push event

    :return: list of container names

    """
    cmds = ['git', 'diff', '--name-only']

    if before_sha and after_sha:
        cmds.extend([before_sha, after_sha])

    logger.debug(f'Executing git diff command: {cmds}')
    result = subprocess.run(cmds, capture_output=True, text=True)
    if result.returncode != 0:
        logger.error(f'Failed to run command: {cmds}, result: {result.stderr}')
        sys.exit(1)

    logger.debug(f'Execute git diff result: {result.stdout}')
    diff_files = result.stdout.strip().split('\n')
    logger.debug(f'Git diff all files: {diff_files}')

    changed_containers_name: set[str] = set()

    containers_path = {}

    for group in project_metadata.container_roups:
        for container in group.containers:
            containers_path[container.name] = container.path

    containers_pattern = regex_pattern_builder(containers_path)

    global_paths_pattern = project_metadata.global_paths

    logger.debug(f'All container names: {containers_path}, global paths: {global_paths_pattern}')

    for changed_file in diff_files:
        # if global path is changed, all containers should be built
        if calculate_global_path_changed(changed_file, global_paths_pattern):
            changed_containers_name = containers_path.keys()
            break

        changed_container = calculate_container_changed(changed_file, containers_pattern)
        if changed_container:
            changed_containers_name.add(changed_container)
        else:
            logger.debug(f'Ignore path: {changed_file}, not matched with any container pattern')

    logger.info(f'Changed containers: {changed_containers_name}')
    return list(changed_containers_name)


def calculate_global_path_changed(changed_file: str, global_paths_pattern: list[str]) -> bool | None:
    """
    Check if the changed file is in the global path

    :return: bool

    """
    for global_path in global_paths_pattern:
        # use glob to match the full path of changed files,
        # if the changed file is in the global path, all containers should be built
        matches = glob.glob(global_path, recursive=True)
        if changed_file in matches:
            logger.info(f'Found global path: {global_path}, all containers should be built')
            return True


def calculate_container_changed(changed_file: str, containers_pattern: dict[str, Path]) -> str | None:
    """
    Caculate the changed container name by the changed file and containers pattern

    :param changed_file: the changed file
    :param containers_pattern: dict of container name and glob pattern

    :return:

    """
    changed_names = set()
    for name, path in containers_pattern.items():
        # use glob to match the full path of changed files
        # if the changed file is in the path, the container should be built
        matches = glob.glob(str(path), recursive=True)
        if changed_file in matches:
            changed_names.add(name)
    if len(changed_names) > 1:
        raise CaculateError(f'More than one container matched the changed file: {changed_file}, matched container: {changed_names}')

    return changed_names.pop() if changed_names else None


def regex_pattern_builder(paths: dict[str, Path]) -> dict[str, Path]:
    """

    Build the container directory regex pattern for the container names

    :param names: list of container names

    :return: dict of container name and the directory regex pattern

    """
    all_patterns: dict[str, Path] = {}
    for name, path in paths.items():
        if not_regex_pattern.match(name):
            if path.exists() and path.is_dir():
                all_patterns.setdefault(name, f'{path}/**/*')
            else:
                logger.warning(f'Invalid container: {name}, {path} does not exists or is not a directory')
        else:
            # Do not recommend to use glob pattern as a product name
            logger.warning(f'Container should be a directory name, not a regex pattern: <{name}: {path}>')
            all_patterns.setdefault(name, path)
    return all_patterns


def get_change_container_groups(project_metadata: ProjectMetadata, changed_containers: list[str]) -> dict[str, list[str]]:
    """
    Get the changed container groups by the changed container names

    :param project_metadata: ProjectMetadata
    :param changed_containers: list of changed container names

    :return: list of ContainerGroup

    example output data
    {
        "group1": ["container1:version1", "container2:version1"],
        "group2": ["container3:version1"],
        "group3": []
    }
    """
    changed_groups: dict[str, list[str]] = {}

    for group in project_metadata.container_roups:
        group_name = group.name
        containers = []
        for container in group.containers:
            if container.name in changed_containers:
                containers.extend([f'{container.name}:{c.version}' for c in container.versions])
        changed_groups[group_name] = containers

    logger.debug(f'Changed container groups: {changed_groups}')
    return changed_groups


def save_output_file(output_file: str, data: dict) -> None:
    """
    Save the output data to the output file

    :param output_file: the path of the output file
    :param data: the output data

    :return: None
    """
    with open(output_file, 'w', encoding=ENCODING) as f:
        json.dump(data, f, indent=2)
    logger.debug(f'Saved data to {output_file}: {data}')
    logger.info(f'Saved output to {output_file}')


def run(
    before_sha: str | None = None,
    after_sha: str | None = None,
    output_file: str = 'output.json',
):
    logger.info('Start to get target container names')

    project_metadata = load_project_metadata()
    changed_containers = get_changed_container_name(project_metadata, before_sha, after_sha)

    changed_groups = get_change_container_groups(project_metadata, changed_containers)

    save_output_file(output_file=output_file, data=changed_groups)


def main():
    # check python version, only support python3.11+
    check_python_version()

    parser = argparse.ArgumentParser()
    parser.add_argument('--before-sha', type=str, required=False, help='The SHA of the commit before the event, default is BEFORE_COMMIT_SHA in the environment')
    parser.add_argument('--after-sha', type=str, required=False, help='The SHA of the commit after the push event, default is AFTER_COMMIT_SHA in the environment')
    parser.add_argument('--output-file', type=str, required=False, default='output.json', help='The path of the output file')
    parser.add_argument('--debug', action='store_true', help='Enable debug mode')

    args = parser.parse_args()

    if args.debug:
        logger.setLevel(logging.DEBUG)

    logger.debug(f'args: {args}')

    if not args.before_sha:
        args.before_sha = os.environ.get('BEFORE_COMMIT_SHA')
    if not args.after_sha:
        args.after_sha = os.environ.get('AFTER_COMMIT_SHA')

    try:
        run(
            before_sha=args.before_sha,
            after_sha=args.after_sha,
            output_file=args.output_file,
        )
    except Exception as e:
        logger.exception(f'Failed to run the script, error: {e}')
        sys.exit(1)


if __name__ == '__main__':
    main()
