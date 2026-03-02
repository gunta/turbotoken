(defproject com.turbotoken/turbotoken-clj "0.1.0"
  :description "Clojure bindings for turbotoken -- the fastest BPE tokenizer"
  :url "https://github.com/turbotoken/turbotoken"
  :license {:name "MIT"
            :url "https://opensource.org/licenses/MIT"}
  :dependencies [[org.clojure/clojure "1.11.1"]]
  :java-source-paths ["../java/src/main/java"]
  :resource-paths ["resources"]
  :profiles {:test {:dependencies []}}
  :source-paths ["src"]
  :test-paths ["test"])
