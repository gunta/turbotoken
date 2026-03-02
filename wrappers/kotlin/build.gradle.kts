plugins {
    kotlin("jvm") version "1.9.23"
}

group = "com.turbotoken"
version = "0.1.0"

repositories {
    mavenCentral()
}

java {
    sourceCompatibility = JavaVersion.VERSION_11
    targetCompatibility = JavaVersion.VERSION_11
}

kotlin {
    jvmToolchain(11)
}

dependencies {
    implementation(kotlin("stdlib"))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.0")

    // Java binding dependency (in a real multi-module build this would be a project dependency)
    implementation(files("../java/target/classes"))

    testImplementation(kotlin("test"))
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.0")
}

tasks.test {
    useJUnitPlatform()
}

sourceSets {
    main {
        java {
            // Include Java sources so Kotlin can reference them directly during development
            srcDir("../java/src/main/java")
        }
    }
}
