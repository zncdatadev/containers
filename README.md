# ZNCDataDev Containers

This repository contains the Dockerfiles for the ZNCDataDev containers.

<!-- start:bages generated by readme-generator.sh -->
|      |      |      |      |
| ---: | ---: | ---: | ---: |
| [![Build airflow]][build_airflow.yaml] | [![Build dolphinscheduler]][build_dolphinscheduler.yaml] | [![Build go-devel]][build_go-devel.yaml] | [![Build hadoop]][build_hadoop.yaml] |
| [![Build hbase]][build_hbase.yaml] | [![Build hive]][build_hive.yaml] | [![Build java-base]][build_java-base.yaml] | [![Build java-devel]][build_java-devel.yaml] |
| [![Build kafka]][build_kafka.yaml] | [![Build krb5]][build_krb5.yaml] | [![Build kubedoop-base]][build_kubedoop-base.yaml] | [![Build nifi]][build_nifi.yaml] |
| [![Build spark-k8s]][build_spark-k8s.yaml] | [![Build superset]][build_superset.yaml] | [![Build testing-tools]][build_testing-tools.yaml] | [![Build tools]][build_tools.yaml] |
| [![Build trino]][build_trino.yaml] | [![Build zookeeper]][build_zookeeper.yaml] | | |

<!-- end:bages -->

## Usage

### Setup docker with buildx

TODO: ref docker doc

### Build

Use the [build.sh](./.scripts/build.sh) script to build the images.

The following command will build the hadoop:3.3.4 and all variants of the zookeeper image.

```bash
./.scripts/build.sh hadoop:3.3.4 zookeeper
```

### Build and push

When enable push, multiple-arch images will be built and pushed to the registry.

```bash
./.scripts/build.sh hadoop:3.3.4 --push
```

### Build and push with sign

When enable sign, the cosign tool should be installed and the image will be signed.

```bash
./.scripts/build.sh hadoop:3.3.4 --push --sign
```

### Set the registry and version

The [build.sh](./.scripts/build.sh) script use environment variables to set the registry and version.

```bash
export REGISTRY=registry.example.com/zncdatadev
export KUBEDOOP_VERSION=0.1.0
./scripts/build.sh kubedoop-base --push
```

<!-- start:links generated by readme-generator.sh -->
[Build airflow]: https://github.com/zncdatadev/containers/actions/workflows/build_airflow.yaml/badge.svg
[build_airflow.yaml]: https://github.com/zncdatadev/containers/actions/workflows/build_airflow.yaml
[Build dolphinscheduler]: https://github.com/zncdatadev/containers/actions/workflows/build_dolphinscheduler.yaml/badge.svg
[build_dolphinscheduler.yaml]: https://github.com/zncdatadev/containers/actions/workflows/build_dolphinscheduler.yaml
[Build go-devel]: https://github.com/zncdatadev/containers/actions/workflows/build_go-devel.yaml/badge.svg
[build_go-devel.yaml]: https://github.com/zncdatadev/containers/actions/workflows/build_go-devel.yaml
[Build hadoop]: https://github.com/zncdatadev/containers/actions/workflows/build_hadoop.yaml/badge.svg
[build_hadoop.yaml]: https://github.com/zncdatadev/containers/actions/workflows/build_hadoop.yaml
[Build hbase]: https://github.com/zncdatadev/containers/actions/workflows/build_hbase.yaml/badge.svg
[build_hbase.yaml]: https://github.com/zncdatadev/containers/actions/workflows/build_hbase.yaml
[Build hive]: https://github.com/zncdatadev/containers/actions/workflows/build_hive.yaml/badge.svg
[build_hive.yaml]: https://github.com/zncdatadev/containers/actions/workflows/build_hive.yaml
[Build java-base]: https://github.com/zncdatadev/containers/actions/workflows/build_java-base.yaml/badge.svg
[build_java-base.yaml]: https://github.com/zncdatadev/containers/actions/workflows/build_java-base.yaml
[Build java-devel]: https://github.com/zncdatadev/containers/actions/workflows/build_java-devel.yaml/badge.svg
[build_java-devel.yaml]: https://github.com/zncdatadev/containers/actions/workflows/build_java-devel.yaml
[Build kafka]: https://github.com/zncdatadev/containers/actions/workflows/build_kafka.yaml/badge.svg
[build_kafka.yaml]: https://github.com/zncdatadev/containers/actions/workflows/build_kafka.yaml
[Build krb5]: https://github.com/zncdatadev/containers/actions/workflows/build_krb5.yaml/badge.svg
[build_krb5.yaml]: https://github.com/zncdatadev/containers/actions/workflows/build_krb5.yaml
[Build kubedoop-base]: https://github.com/zncdatadev/containers/actions/workflows/build_kubedoop-base.yaml/badge.svg
[build_kubedoop-base.yaml]: https://github.com/zncdatadev/containers/actions/workflows/build_kubedoop-base.yaml
[Build nifi]: https://github.com/zncdatadev/containers/actions/workflows/build_nifi.yaml/badge.svg
[build_nifi.yaml]: https://github.com/zncdatadev/containers/actions/workflows/build_nifi.yaml
[Build spark-k8s]: https://github.com/zncdatadev/containers/actions/workflows/build_spark-k8s.yaml/badge.svg
[build_spark-k8s.yaml]: https://github.com/zncdatadev/containers/actions/workflows/build_spark-k8s.yaml
[Build superset]: https://github.com/zncdatadev/containers/actions/workflows/build_superset.yaml/badge.svg
[build_superset.yaml]: https://github.com/zncdatadev/containers/actions/workflows/build_superset.yaml
[Build testing-tools]: https://github.com/zncdatadev/containers/actions/workflows/build_testing-tools.yaml/badge.svg
[build_testing-tools.yaml]: https://github.com/zncdatadev/containers/actions/workflows/build_testing-tools.yaml
[Build tools]: https://github.com/zncdatadev/containers/actions/workflows/build_tools.yaml/badge.svg
[build_tools.yaml]: https://github.com/zncdatadev/containers/actions/workflows/build_tools.yaml
[Build trino]: https://github.com/zncdatadev/containers/actions/workflows/build_trino.yaml/badge.svg
[build_trino.yaml]: https://github.com/zncdatadev/containers/actions/workflows/build_trino.yaml
[Build zookeeper]: https://github.com/zncdatadev/containers/actions/workflows/build_zookeeper.yaml/badge.svg
[build_zookeeper.yaml]: https://github.com/zncdatadev/containers/actions/workflows/build_zookeeper.yaml

<!-- end:links -->
