## Quickstart

Clone repository

```bash
git clone https://github.com/OpenMandrivaSoftware/rhel-builder.git
```

Create basic image
```bash
sh mkimage-yum.sh -y yum.conf rels
```
Create builder image:

```bash
cd docker-builder
docker build --tag=rosalab/builder:rels75 --file Dockerfile.builder .
```

## Remove stopped containers
```bash
docker rm -v $(docker ps -a -q -f status=exited)
```

## Run abf builder
```bash
docker run -ti --rm --privileged=true -h <yourname>.openmandriva.org -e BUILD_TOKEN="your_token" \
	-e BUILD_ARCH="x86_64 armv7hl i586 i686 aarch64" \
	 -e BUILD_PLATFORM="cooker" rosalab/builder:rels75
```
