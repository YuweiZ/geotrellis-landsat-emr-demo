name := "server"
scalaVersion := Version.scala
javaOptions += "-Xmx4G"

fork in run := true

connectInput in run := true

libraryDependencies ++= Seq(
  "org.locationtech.geotrellis" %% "geotrellis-spark" % Version.geotrellis,
  "org.locationtech.geotrellis" %% "geotrellis-s3" % Version.geotrellis,
  "org.locationtech.geotrellis" %% "geotrellis-accumulo" % Version.geotrellis,
  "org.locationtech.geotrellis" %% "geotrellis-hbase" % Version.geotrellis,
  "org.locationtech.geotrellis" %% "geotrellis-cassandra" % Version.geotrellis,
  "org.apache.spark"      %% "spark-core" % "2.0.0" % "provided",
  "com.typesafe.akka"     %% "akka-actor" % "2.3.15",
  Dependencies.sprayRouting,
  Dependencies.sprayCan,
  "org.scalatest"       %%  "scalatest"      % "3.0.0" % "test"
)

assemblyMergeStrategy in assembly := {
  case "reference.conf" => MergeStrategy.concat
  case "application.conf" => MergeStrategy.concat
  case "META-INF/MANIFEST.MF" => MergeStrategy.discard
  case "META-INF\\MANIFEST.MF" => MergeStrategy.discard
  case "META-INF/ECLIPSEF.RSA" => MergeStrategy.discard
  case "META-INF/ECLIPSEF.SF" => MergeStrategy.discard
  case _ => MergeStrategy.first
}

Revolver.settings

assemblyShadeRules in assembly := {
  val shadePackage = "com.azavea.shaded.demo"
  Seq(
    ShadeRule.rename("com.google.common.**" -> s"$shadePackage.google.common.@1")
      .inLibrary("org.locationtech.geotrellis" %% "geotrellis-cassandra" % Version.geotrellis).inAll
  )
}
