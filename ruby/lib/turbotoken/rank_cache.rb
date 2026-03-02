require "net/http"
require "uri"
require "fileutils"

module TurboToken
  module RankCache
    CACHE_SUBDIR = "turbotoken"

    def self.cache_dir
      base = ENV["TURBOTOKEN_CACHE_DIR"] ||
        File.join(ENV.fetch("XDG_CACHE_HOME", File.expand_path("~/.cache")), CACHE_SUBDIR)
      FileUtils.mkdir_p(base)
      base
    end

    def self.ensure_rank_file(name)
      spec = Registry.get_encoding_spec(name)
      path = File.join(cache_dir, "#{name}.tiktoken")

      if File.exist?(path)
        read_rank_file(path)
      else
        download_rank_file(spec.rank_file_url, path)
      end
    end

    def self.read_rank_file(path)
      File.binread(path)
    end

    def self.download_rank_file(url, dest_path)
      uri = URI.parse(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(Net::HTTP::Get.new(uri))
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "Failed to download rank file from #{url}: HTTP #{response.code}"
      end

      FileUtils.mkdir_p(File.dirname(dest_path))
      File.binwrite(dest_path, response.body)
      response.body
    end
  end
end
