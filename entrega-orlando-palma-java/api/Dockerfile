# Etapa 1: compilacion con Maven y JDK 21
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app

# Primero el pom, para que la capa de dependencias quede en cache
COPY pom.xml .
RUN mvn -B -q dependency:go-offline

COPY src ./src
RUN mvn -B -q package -DskipTests

# Etapa 2: runtime solo con el JRE
FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /app/target/orders-api.jar app.jar

ENV PORT=5002
EXPOSE 5002

ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "app.jar"]
