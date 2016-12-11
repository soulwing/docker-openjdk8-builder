docker-openjdk8-builder
=======================

A Docker image for building OpenJDK 8.

This Docker image is a complete environment for building OpenJDK 8 from source, based on Debian Jessie, and is intended to serve as a basis for building Docker images that incorporate OpenJDK 8.

The OpenJDK 8 build is scripted based on previous work by [Henri Gomez](https://github.com/hgomez) in
[OBuildFactory](https://github.com/hgomez/obuildfactory).


Usage
-----

To fetch the OpenJDK source tree and build the HEAD version, simply run the image.

```
docker run -ti soulwing/openjdk8-builder
```

After the container exits from a successful build, the resulting JVM images can be found in 
the container's `/openjdk/build/openjdk8/build/linux-x86_64-normal-server-release/images/`. See 
[Obtaining the Build Result](#obtaining-the-build-result) below for suggestions on how to obtain the resulting JVM images from the container.

### Mounting the Source Tree

If you don't want to have to fetch the OpenJDK source tree before each build, you can mount a host filesystem onto the container's `/openjdk/sources` directory. If, for example, you wanted to mount the host's `/var/src/openjdk8` you would run as follows.

```
docker run -v /var/src/openjdk8:/openjdk/sources -ti soulwing/openjdk8-builder
```

### Building a Specific Update

Specify the `XUSE_UPDATE` environment variable. For example, to build version 8u112 (1.8.0_112), run as follows.

```
docker run -e XUSE_UPDATE=112 -ti soulwing/openjdk8-builder
```

Obtaining the Build Result
--------------------------

After the build finishes, the resulting JVM images will be on the filesystem of the exited container at the
following path.

```
/openjdk/build/openjdk8/build/linux-x86_64-normal-server-release/images/
```

You can easily retrieve them from the container's filesystem using Docker's copy command. Get the ID of the exited container using `docker ps -qa`, then use the copy command.

```
docker cp ${container_id}:/openjdk/build/openjdk8/build/linux-x86_64-normal-server-release/images/ openjdk8/
```

This will copy the JVM images from the container filesystem to the `openjdk8/` directory on the host's filesystem.

If you want to fully script the build and extract the image, you'll probably want to create the container and then start it. The accomplishes the same thing as the `run` command, but allows the container ID to be captured when it is created.

```
container_id=$(docker create -e XUSE_UPDATE=112 -t soulwing/openjdk8-builder)
docker start -a -i $container_id
docker cp $container_id:/openjdk/build/openjdk8/build/linux-x86_64-normal-server-release/images/ openjdk8/
docker rm $container_id
```

Note that after the JVM images have been copied from the build container, the last command removes the container. Each build container is fairly large, so you'll want to clean them up to avoid consuming lots of disk space with finished builds.

