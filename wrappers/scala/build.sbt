name := "turbotoken-scala"
version := "0.1.0"
organization := "com.turbotoken"
homepage := Some(url("https://github.com/turbotoken/turbotoken/tree/main/wrappers/scala"))
licenses += ("MIT", url("https://opensource.org/licenses/MIT"))
scmInfo := Some(
  ScmInfo(
    url("https://github.com/turbotoken/turbotoken"),
    "scm:git:https://github.com/turbotoken/turbotoken.git"
  )
)

scalaVersion := "3.3.1"
crossScalaVersions := Seq("2.13.12", "3.3.1")

// Depend on the Java turbotoken jar
unmanagedJars in Compile += file("../java/build/libs/turbotoken.jar")

libraryDependencies ++= Seq(
  "org.scalatest" %% "scalatest" % "3.2.17" % Test
)

// Compiler options
scalacOptions ++= Seq(
  "-deprecation",
  "-encoding", "UTF-8",
  "-feature",
  "-unchecked"
)
