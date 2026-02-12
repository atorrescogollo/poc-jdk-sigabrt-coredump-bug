# Summary of targets:
# - amazoncorretto-25-patched-build: Patched Amazon Corretto 25 build image with build artifacts
# - amazoncorretto-25-patched: Patched Amazon Corretto 25 image meant to be used as a base image
# - amazoncorretto-25: Alias to easily switch between amazoncorretto-25-patched and amazoncorretto:25

# ================================================
#     CUSTOM VERSION OF AMAZON CORRETTO 25
# ================================================
FROM amazoncorretto:25-al2023 AS amazoncorretto-25-patched-build
RUN dnf install wget tar gzip -y
RUN wget https://github.com/corretto/corretto-25/archive/refs/tags/25.0.2.10.1.tar.gz \
     && tar vxzf 25.0.2.10.1.tar.gz && mv -v corretto-25-* /corretto-25
RUN dnf groupinstall "Development Tools" -y
RUN dnf install \
     alsa-lib-devel \
     cups-devel \
     fontconfig-devel \
     freetype-devel \
     harfbuzz-devel \
     libXtst-devel libXt-devel libXrender-devel libXrandr-devel libXi-devel \
     -y

WORKDIR /corretto-25
# https://mail.openjdk.org/pipermail/hotspot-dev/2026-February/118622.html
COPY jdk25.patch /patches/jdk25.patch
RUN patch -p0 < /patches/jdk25.patch
# https://github.com/corretto/corretto-25/blob/5c8c2878637da87c541cfd91e5ed6ba2259d961a/build.gradle#L87-L97
RUN bash ./configure \
    --with-vendor-name="Amazon.com Inc." \
    --with-vendor-url="https://aws.amazon.com/corretto/" \
    --with-vendor-bug-url="https://github.com/corretto/corretto-jdk/issues/" \
    --with-vendor-vm-bug-url="https://github.com/corretto/corretto-jdk/issues/"
RUN make images
RUN rm -rf "/usr/lib/jvm/java-25-amazon-corretto.$(uname -m)" && mv -v /corretto-25/build/*/images/jdk /usr/lib/jvm/java-25-amazon-corretto.$(uname -m)

FROM scratch AS amazoncorretto-25-patched
COPY --from=amazoncorretto:25-al2023 --exclude=/usr/lib/jvm/ / /
COPY --from=amazoncorretto-25-patched-build /usr/lib/jvm/ /usr/lib/jvm/
# https://github.com/corretto/corretto-docker/blob/d16498c662b9676715ac207de2dcd674358e8b2d/25/headless/al2023/Dockerfile
ENV LANG=C.UTF-8
ENV JAVA_HOME=/usr/lib/jvm/java-25-amazon-corretto


# ================================================
#     ACTUAL APP BUILD IMAGE
# ================================================
# Uncomment the base image you want to use
FROM amazoncorretto:25 AS amazoncorretto-25
#FROM amazoncorretto-25-patched AS amazoncorretto-25

FROM amazoncorretto-25 AS builder

# Install build tools
RUN yum install -y gcc glibc-devel

# Set working directory
WORKDIR /build

# Copy project files
COPY . .

# Make gradlew executable and build
RUN chmod +x gradlew && ./gradlew clean build -x test

# Runtime stage
FROM amazoncorretto-25

WORKDIR /app

# Copy built JAR from builder
COPY --from=builder /build/build/libs/*.jar app.jar

# Expose port
EXPOSE 8080

# Run application
ENTRYPOINT ["java", "-jar", "app.jar"]
