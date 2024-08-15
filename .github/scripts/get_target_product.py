#!/usr/bin/env python3

# Note: supported python3.11+

import argparse
import dataclasses
import glob
import json
import logging
import os
from pathlib import Path
import re
import sys
import subprocess


logging.basicConfig(
    level=logging.DEBUG if os.environ.get('CI_SCRIPT_DEBUG') else logging.INFO, 
    format='%(asctime)s - %(name)s - %(levelname)s - %(lineno)d - %(message)s',
)

logger = logging.getLogger(__name__)

PROJECT_METADATA_FILE_NAME = 'project.json'
PROEUCT_METADATA_FILE_NAME = 'metadata.json'
ENCODING = 'utf-8'

not_glob_pattern = re.compile(r'^[^*?\[\]]*$')


@dataclasses.dataclass
class ProjectMetadata:
    products_priority: dict[str, int]
    infra_priority: dict[str, int]
    global_paths: list[str]


@dataclasses.dataclass
class ProductUpstream:
    name: str 
    version: str


@dataclasses.dataclass
class ProductProperty:
    upstream: ProductUpstream | None
    dependencies: dict[str, str] | None # key: package name, value: version


@dataclasses.dataclass
class ProductMetadata:
    name: str
    priority: int
    properties: list[ProductProperty]
    
    def __repr__(self) -> str:
        return f'ProductMetadata(name={self.name}, priority={self.priority})'


def load_project_metadata(metadata_path: Path = Path(PROJECT_METADATA_FILE_NAME)) -> ProjectMetadata:
    with open(metadata_path, 'r', encoding='utf-8') as f:
        metadata = json.load(f)

    logger.debug(f'loaded project metadata from {metadata_path}: {metadata}')
    return ProjectMetadata(
        products_priority=metadata.get('products_priority', {}), 
        global_paths=metadata.get('global_path', []),
        infra_priority=metadata.get('infra_priority', {}),
    )


def load_product_metadata(product_name: str, priority: int) -> ProductMetadata:
    metadata_path = Path(f'{product_name}/{PROEUCT_METADATA_FILE_NAME}')
    
    with open(metadata_path, 'r', encoding='utf-8') as f:
        metadata = json.load(f)
    logger.debug(f'loaded product metadata from {metadata_path}: {metadata}')
    
    name = metadata['name']
    properties: list[ProductProperty] = []
    
    for property in metadata['properties']:
        upstream_dict = property.get('upstream') # optional
        dependencies: dict[str, str] = property.get('dependencies') # optional
        product_property = ProductProperty(dependencies=dependencies, upstream=None)
        if upstream_dict:
            upstream_name = upstream_dict['name']
            upstream_version = upstream_dict['version']
            product_property = ProductProperty(
                upstream=ProductUpstream(name=upstream_name, version=upstream_version),
                dependencies=dependencies
            )
        properties.append(product_property)
        logger.debug(f'loaded product property: {product_property}')
    
    return ProductMetadata(name=name, priority=priority, properties=properties)



def get_changed_product_name(
    project_metadata: ProjectMetadata,
    before_sha: str| None = None,
    after_sha: str | None = None
) -> list[str]:
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
    
    changed_product_name: set[str] = set()
    
    all_product_names = set(list(project_metadata.products_priority.keys()) + list(project_metadata.infra_priority.keys()))

    # check if the product name is a glob pattern, if not, convert it to a glob pattern
    # Usually, products_priority and infra_priority are project name, it is not a glob pattern,
    # but we need to check the full path of changed files  with glob pattern, to match which product should be built
    # so we need to convert the product name to a glob pattern
    all_product_patterns: dict[str, str] = {}
    for product_name in all_product_names:
        product_path = Path(product_name)
        if not_glob_pattern.match(product_name):
            if product_path.exists() and product_path.is_dir():
                all_product_patterns.setdefault(product_name, f'{product_name}/**/*')
            else:
                logger.warning(f'Invalid product name: {product_name} or not exists')
    
    global_paths = project_metadata.global_paths
    logger.debug(f'All product names: {all_product_names}, global paths: {global_paths}')

    for changed_file in diff_files:
        added = False   # debug flag
        for global_path in global_paths:
            # use glob to match the full path of changed files,
            # if the changed file is in the global path, all products should be built
            matches = glob.glob(global_path, recursive=True)
            if changed_file in matches:
                logger.info(f'Found global path: {global_path}, all products should be built')
                changed_product_name = all_product_names
                break
        for product, product_pattern in all_product_patterns.items():
            # use glob to match the full path of changed files
            # if the changed file is in the product path, the product should be built
            matches = glob.glob(product_pattern, recursive=True)
            if changed_file in matches:
                changed_product_name.add(product)
                logger.info(f'Found changed product: {changed_file}')
                added = True
                break
        if not added:
            logger.debug(f'Ignore path: {changed_file}, not matched with any product pattern')

    logger.info(f'Changed product names: {changed_product_name}')
    return list(changed_product_name)


def get_product_metadata(product_names: list[str], priority: dict[str, int]) -> list[ProductMetadata]:
    product_metadata: list[ProductMetadata] = []
    
    for product_name in product_names:
        if product_name in priority:
            product_metadata.append(load_product_metadata(product_name, priority[product_name]))
    
    # sort by priority
    product_metadata.sort(key=lambda x: x.priority)
    
    loaded_product_names = {product.name: product.priority for product in product_metadata}
    logger.info(f'Loaded product metadata: {loaded_product_names}')
    return product_metadata


def save_output(
    data: dict[str, list[str]],
    file: Path = Path('output.json')
):
    with open(file, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2)
    logger.info(f'Saved data to the file: {file}')

def run(
    before_sha: str | None = None,
    after_sha: str | None = None,
    metadata_path: str | None = None,
    output_file: str = 'output.json',
):
    logger.info(f'Start to get target product names')
    
    metadata = load_project_metadata(Path(metadata_path))
    
    changed_product_name = get_changed_product_name(project_metadata=metadata, before_sha=before_sha, after_sha=after_sha) 
    changed_product = get_product_metadata(changed_product_name, metadata.products_priority)
    changed_infra = get_product_metadata(changed_product_name, metadata.infra_priority)
    logger.info(f'Changed product: {changed_product}, Changed infra product: {changed_infra}')
    
    data={
        'products': [product.name for product in changed_product], 
        'infra': [product.name for product in changed_infra],
    }
    
    save_output(data=data, file=Path(output_file)) 
    logger.info(f'Saved product names to the output file: {output_file}')
    
    logger.info(f'Finished to get target product names')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--before-sha', type=str, required=False, help='The SHA of the commit before the event, default is BEFORE_COMMIT_SHA in the environment')
    parser.add_argument('--after-sha', type=str, required=False, help='The SHA of the commit after the push event, default is AFTER_COMMIT_SHA in the environment')
    parser.add_argument('--metadata-path', type=str, required=False, default='project.json', help='The path of the metadata file')
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
            metadata_path=args.metadata_path,
        )
    except Exception as e:
        logger.exception(f'Failed to run the script, error: {e}')
        sys.exit(1)


main()
