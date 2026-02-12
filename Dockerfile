FROM amazoncorretto:25 AS builder

# Install build tools
RUN yum install -y gcc glibc-devel

# Set working directory
WORKDIR /build

# Copy project files
COPY . .

# Make gradlew executable and build
RUN chmod +x gradlew && ./gradlew clean build -x test

# Runtime stage
FROM amazoncorretto:25

WORKDIR /app

# Copy built JAR from builder
COPY --from=builder /build/build/libs/*.jar app.jar

# Expose port
EXPOSE 8080

# Run application
ENTRYPOINT ["java", "-jar", "app.jar"]
