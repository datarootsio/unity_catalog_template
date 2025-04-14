# Use Amazon Corretto JDK 17 on Alpine Linux
FROM amazoncorretto:17-alpine3.20-jdk AS builder

# Set working directoryx
WORKDIR /app

# Install necessary dependencies
RUN apk update && apk add --no-cache \
    curl \
    bash \
    unzip \
    git

# Clone Unity Catalog repository
ARG UC_VERSION="0.2.1"
RUN wget https://github.com/unitycatalog/unitycatalog/archive/refs/tags/v${UC_VERSION}.zip \
    && unzip v${UC_VERSION}.zip \
    && mv unitycatalog-${UC_VERSION} unitycatalog \
    && rm v${UC_VERSION}.zip

# Install SBT
RUN curl -L -o sbt-1.9.9.tgz https://github.com/sbt/sbt/releases/download/v1.9.9/sbt-1.9.9.tgz && \
    tar -xvzf sbt-1.9.9.tgz && \
    mv sbt /usr/local && \
    rm sbt-1.9.9.tgz

# Add SBT to PATH
ENV PATH="/usr/local/sbt/bin:${PATH}"

# Build Unity Catalog using SBT
WORKDIR /app/unitycatalog
RUN sbt clean compile package

# ---- Build Final Lightweight Runtime Image ----
FROM alpine:3.20 AS runtime

# Set environment variables
ARG JAVA_HOME="/usr/lib/jvm/default-jvm"
ARG USER="unitycatalog"
ARG HOME="/app/unitycatalog"
ENV HOME=$HOME

# Install only necessary runtime dependencies
RUN apk update && apk add --no-cache bash

# Copy Java from builder stage
COPY --from=builder $JAVA_HOME $JAVA_HOME

# Set PATH for Java
ENV JAVA_HOME=$JAVA_HOME
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# Copy compiled Unity Catalog files
COPY --from=builder $HOME $HOME
COPY --from=builder /root/.cache/ /root/.cache/

# Set working directory and create a user for security
WORKDIR $HOME
RUN addgroup -S $USER && adduser -S -G $USER $USER \
    && chmod -R 550 $HOME \
    && mkdir -p $HOME/etc/ \
    && chmod -R 775 $HOME/etc/ \
    && chown -R $USER:$USER $HOME

# Expose port 8080
EXPOSE 8080

# Start Unity Catalog server
CMD ["bin/start-uc-server"]
#i want to run these comands after the start
#CMD ["cat etc/conf/token.txt"]
#CMD ["bin/uc --auth_token $(cat etc/conf/token.txt) permission create  --securable_type catalog --name unity --privilege 'USE CATALOG' --principal admin"]
#CMD ["bin/uc --auth_token $(cat etc/conf/token.txt) permission create  --securable_type catalog --name unity --privilege 'CREATE SCHEMA' --principal admin"]