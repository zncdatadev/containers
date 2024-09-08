#!/usr/bin/env python3
# Note: only supported python3.11+

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


@dataclasses.dataclass
class ChangedProducts:
    products: list[str]
    infra: list[str]


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
    
    Project metadata contains infra_priority, products_priority, and global_paths.
    
    * infra_priority is infrastructure product name and priority, the priority is used to sort the product build order.
    infra product is the basic level of the product, it should be built first. And some infra product depends on other infra products.
    priority is infra product relationship, the smaller number is lower level infra product, it should be built first.
    
    * products_priority is a dict of product name and priority, the priority is used to sort the product build order.
    final products priority number unimportant, it only used to sort the product build order.
    
    * global_paths is a list of glob pattern, if the changed file is in the global path, all products should be built.
    Usually, it contains some scripts, configuration files, etc.
    
    
    :param metadata_path: the path of the metadata file
    
    :return: ProjectMetadata
    
    """
    with open(metadata_path, 'r', encoding='utf-8') as f:
        metadata = json.load(f)

    logger.debug(f'loaded project metadata from {metadata_path}: {metadata}')
    return ProjectMetadata(
        products_priority=metadata.get('products_priority', {}), 
        global_paths=metadata.get('global_path', []),
        infra_priority=metadata.get('infra_priority', {}),
    )


def load_product_metadata(product_name: str, priority: int) -> ProductMetadata:
    """
    Load product metadata from the metadata.json file in the product directory
    
    :param product_name: the product name
    :param priority: the priority of the product
    
    :return: ProductMetadata
    """
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


def resolve_changed_product_dependencies_with_priority(
    project_metadata: ProjectMetadata,
    changed_products_name: list[str],
) -> ChangedProducts:
    """
    Resolve the changed product dependencies with priority
    
    * If the infra product is changed, all final products and the priority is higher than the changed products should be built.
    
    :param project_metadata: ProjectMetadata
    :param changed_products_name: list of changed product names
    
    :return: ChangedProducts
    
    """
    infra_names = set(project_metadata.infra_priority.keys())
    final_product_names = set(project_metadata.products_priority.keys())
    
    changed_infra_names = set(changed_products_name) & infra_names
    changed_final_product_names = set(changed_products_name) & final_product_names
    logger.debug(f'Changed infra names: {changed_infra_names}, Changed final product names: {changed_final_product_names}')
    
    # if infra is changed, all final products should be built
    if changed_infra_names:
        changed_final_product_names = final_product_names
    logger.debug(f'Changed final product names: {changed_final_product_names}')

    infra_metadata = get_products_metadata(changed_infra_names, project_metadata.infra_priority)
    final_product_metadata = get_products_metadata(changed_final_product_names, project_metadata.products_priority)
    
    if infra_metadata:
        # get all infra higher than the minimum priority of the changed infra
        min_infra_priority = min([product.priority for product in infra_metadata])
        all_infra_metadata = get_products_metadata(infra_names, project_metadata.infra_priority)
        infra_metadata.extend([product for product in all_infra_metadata if product.priority > min_infra_priority])
    
    return ChangedProducts(
        products=[product.name for product in final_product_metadata],
        infra=[product.name for product in infra_metadata],
    )


def get_changed_product_name(
    project_metadata: ProjectMetadata,
    before_sha: str| None = None,
    after_sha: str | None = None
) -> list[str]:
    """
    Use git diff command to get the changed product between two commits by checking the changed files.
    
    Product metadata contains product and infra product, also define some global paths.
    If the changed file is in the global path, all products should be built.
    Product priority is used to sort the product build order.
    And those infra products priority is higher changed products, it also should be built,
    even if the infra product is not changed. Because higher level products depend on the lower level products.
    
    :param project_metadata: ProjectMetadata
    :param before_sha: the SHA of the commit before the event
    :param after_sha: the SHA of the commit after the push event
    
    :return: list of product names
    
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
    
    changed_product_name: set[str] = set()
    
    all_product_names = set(list(project_metadata.products_priority.keys()) + list(project_metadata.infra_priority.keys()))

    all_products_pattern = convert_product_name_to_glob_pattern(all_product_names)
    
    global_paths_pattern = project_metadata.global_paths
    
    logger.debug(f'All product names: {all_product_names}, global paths: {global_paths_pattern}')

    for changed_file in diff_files:

        if calculate_global_path_changed(changed_file, global_paths_pattern):
            changed_product_name = all_product_names
            break
        
        product = calculate_product_changed(changed_file, all_products_pattern)
        if product:
            changed_product_name.add(product)
        else:
            logger.debug(f'Ignore path: {changed_file}, not matched with any product pattern')

    logger.info(f'Changed product names: {changed_product_name}')
    return list(changed_product_name)


def calculate_global_path_changed(changed_file: str, global_paths_pattern: list[str]) -> bool:
    """
    Check if the changed file is in the global path
    
    :return: bool
    
    """
    for global_path in global_paths_pattern:
        # use glob to match the full path of changed files,
        # if the changed file is in the global path, all products should be built
        matches = glob.glob(global_path, recursive=True)
        if changed_file in matches:
            logger.info(f'Found global path: {global_path}, all products should be built')
            return True
    

def calculate_product_changed(changed_file: str, products_pattern: dict[str, str]) -> str:
    """
    Caculate the changed product name by the changed file and product pattern
    
    :param changed_file: the changed file
    :param products_pattern: dict of product name and glob pattern
    
    :return: 
    
    """
    for product, product_pattern in products_pattern.items():
        # use glob to match the full path of changed files
        # if the changed file is in the product path, the product should be built
        matches = glob.glob(product_pattern, recursive=True)
        if changed_file in matches:
            logger.info(f'Found changed product: {changed_file}')
            return product


def convert_product_name_to_glob_pattern(product_names: list[str]| set[set]) -> dict[str, str]:
    """
    check if the product name is a glob pattern, if not, convert it to a glob pattern
    Usually, products_priority and infra_priority are project name, it is not a glob pattern,
    but we need to check the full path of changed files  with glob pattern, to match which product should be built
    so we need to convert the product name to a glob pattern
    
    :param product_names: list of product names
    
    :return: dict of product name and glob pattern
    
    """
    all_product_patterns: dict[str, str] = {}
    for product_name in product_names:
        product_path = Path(product_name)
        if not_glob_pattern.match(product_name):
            if product_path.exists() and product_path.is_dir():
                all_product_patterns.setdefault(product_name, f'{product_name}/**/*')
            else:
                logger.warning(f'Invalid product name: {product_name} or not exists')
        else:
            # Do not recommend to use glob pattern as a product name
            logger.warning(f'Product should be a directory name, not a glob pattern: {product_name}')
            all_product_patterns.setdefault(product_name, product_name)
    return all_product_patterns


def get_products_metadata(product_names: list[str], priority: dict[str, int]) -> list[ProductMetadata]:
    """
    Get the product metadata by the product names and priority, and sort by priority
    
    :param product_names: list of product names
    :param priority: dict of product name and priority
    
    :return: list of ProductMetadata
    """
    product_metadata: list[ProductMetadata] = []
    
    for product_name in product_names:
        if product_name in priority:
            product_metadata.append(load_product_metadata(product_name, priority[product_name]))
    
    # sort by priority
    product_metadata.sort(key=lambda x: x.priority)
    
    loaded_product_names = {product.name: product.priority for product in product_metadata}
    logger.info(f'Loaded product metadata: {loaded_product_names}')
    return product_metadata


def save_output(changed_product: ChangedProducts, file: Path = Path('output.json')):
    products_name = dataclasses.asdict(changed_product)
    with open(file, 'w', encoding='utf-8') as f:
        json.dump(products_name, f, indent=2)
    logger.info(f'Saved data to the file: {file}, data: {products_name}')


def run(
    before_sha: str | None = None,
    after_sha: str | None = None,
    metadata_path: str | None = None,
    output_file: str = 'output.json',
):
    logger.info(f'Start to get target product names')
    
    metadata = load_project_metadata(Path(metadata_path))
    
    changed_products_name = get_changed_product_name(project_metadata=metadata, before_sha=before_sha, after_sha=after_sha)
    
    resolved_products_name = resolve_changed_product_dependencies_with_priority(project_metadata=metadata, changed_products_name=changed_products_name)
    
    save_output(changed_product=resolved_products_name, file=Path(output_file))
     
    logger.info(f'Saved product names to the output file: {output_file}')
    
    logger.info(f'Finished to get target product names')


def main():
    # check python version, only support python3.11+
    check_python_version()
    
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
