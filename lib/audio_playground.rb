require "logger-better"

module AudioPlayground
  def self.logger; @logger; end

  def self.init!
    @logger          = Logger::Better.new(STDOUT)
    @logger.level    = (ENV["SPARKLEMOTION_LOGLEVEL"] || "info").downcase.to_sym
    @logger.progname = caller.last.split(":", 2).first.split(%r{/}).last
  end
end

require_relative "./audio_playground/cli/argument_parser"

require_relative "./audio_playground/task/task"
require_relative "./audio_playground/task/unmanaged_task"
require_relative "./audio_playground/task/managed_task"

require_relative "./audio_playground/audio/input_stream"
require_relative "./audio_playground/audio/device_input_stream"
require_relative "./audio_playground/audio/file_input_stream"

require_relative "./audio_playground/audio/band_pass_filter"

require_relative "./audio_playground/audio/output_stream"
require_relative "./audio_playground/audio/device_output_stream"
