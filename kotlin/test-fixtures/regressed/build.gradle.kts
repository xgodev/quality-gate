plugins {
    kotlin("jvm") version "2.0.21"
    id("org.jetbrains.kotlinx.kover") version "0.8.3"
}

repositories {
    mavenCentral()
}

dependencies {
    testImplementation(kotlin("test"))
}

tasks.test {
    useJUnitPlatform()
    ignoreFailures = true
}

kotlin {
    jvmToolchain(21)
}
