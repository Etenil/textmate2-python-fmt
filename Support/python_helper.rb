#!/usr/bin/env ruby18

require ENV['TM_SUPPORT_PATH'] + '/lib/exit_codes'
require ENV['TM_SUPPORT_PATH'] + '/lib/textmate'
require ENV['TM_SUPPORT_PATH'] + '/lib/tm/executor'
require ENV['TM_SUPPORT_PATH'] + '/lib/tm/process'

$OUTPUT = ""
$TOOLTIP_OUTPUT = []
$DOCUMENT = STDIN.read
$ERROR_LINES = {}

module Python
  module_function
  def env_err(var)
    "err: #{var}"
  end

  def check_env(var)
    return nil if ENV[var]
    return env_err(var)
  end

  def setup
    err = check_env("TM_PYTHON")
    ENV["PATH"] = "#{File.dirname(ENV["TM_PYTHON"])}:#{ENV["PATH"]}" if err.nil?
    err
  end
  
  def boxify(text)
    "#{"-" * 64}\n #{text}\n#{"-" * 64}"
  end

  def reset_markers
    system(
      ENV["TM_MATE"],
      "--uuid",
      ENV["TM_DOCUMENT_UUID"],
      "--clear-mark=note",
      "--clear-mark=warning",
      "--clear-mark=error"
    )
  end
  
  def set_markers
    $ERROR_LINES.each do |line_number, errs|
      out_message = []
      errs.each do |data|
        out_message << "[#{data[:code]}]: #{data[:message]}"
      end
      tm_args = [
        "--uuid",
        ENV["TM_DOCUMENT_UUID"],
        "--line",
        "#{line_number}",
        "--set-mark",
        "error:#{out_message.join("\n")}",
      ]
      system(ENV["TM_MATE"], *tm_args)
    end
  end
  
  def update_errors(input)
    input.split("\n").each do |line|
      line_result = line.split(" || ")

      if line_result.length > 1
        line_number = line_result[0].to_i
        column = line_result[1]
        code = line_result[2]
        message = line_result[3]
        $ERROR_LINES[line_number] = [] unless $ERROR_LINES.has_key?(line_number)
        $ERROR_LINES[line_number] << {
          :column => column,
          :code => code,
          :message => message,
        }
      end
    end
  end

  # callback.document.will-save
  def isort
    cmd = ENV["TM_PYTHON_FMT_ISORT"] || `command -v isort`.chomp
    TextMate.exit_show_tool_tip(boxify("isort binary not found!")) if cmd.empty?

    args = []
    args << "--virtual-env" << ENV["TM_PYTHON_FMT_VIRTUAL_ENV"] if ENV["TM_PYTHON_FMT_VIRTUAL_ENV"]
    args << "-"

    $OUTPUT, err = TextMate::Process.run(cmd, args, :input => $DOCUMENT)
    TextMate.exit_show_tool_tip(err) unless err.nil? || err == ""

    $DOCUMENT = $OUTPUT
  end

  # callback.document.will-save
  def black
    cmd = ENV["TM_PYTHON_FMT_BLACK"] || `command -v black`.chomp
    TextMate.exit_show_tool_tip(boxify("black binary not found!")) if cmd.empty?
    
    args = [
      "-",
    ]
    
    $OUTPUT, err = TextMate::Process.run(cmd, args, :input => $DOCUMENT)
    $DOCUMENT = $OUTPUT
  end
  
  # callback.document.did-save
  def flake8
    cmd = ENV["TM_PYTHON_FMT_FLAKE8"] || `command -v flake8`.chomp
    TextMate.exit_show_tool_tip(boxify("flake8 binary not found!")) if cmd.empty?
    args = [
      "--format",
      "%(row)d || %(col)d || %(code)s || %(text)s",
    ]
    
    out, err = TextMate::Process.run(cmd, args, ENV["TM_FILEPATH"])
    TextMate.exit_show_tool_tip(err) unless err.nil? || err == ""
    
    if out.empty?
      $TOOLTIP_OUTPUT << "\t flake8 👍"
    else
      update_errors(out)
    end
  end
  
  def pylint
    cmd = ENV["TM_PYTHON_FMT_PYLINT"] || `command -v pylint`.chomp
    TextMate.exit_show_tool_tip(boxify("pylint binary not found!")) if cmd.empty?
    args = [
      "--errors-only",
      "--msg-template",
      "{line} || {column} || {msg_id} || {msg}",
    ]

    args += ENV["TM_PYTHON_FMT_PYLINT_EXTRA_OPTIONS"].split if ENV["TM_PYTHON_FMT_PYLINT_EXTRA_OPTIONS"]

    out, err = TextMate::Process.run(cmd, args, ENV["TM_FILEPATH"])
    TextMate.exit_show_tool_tip(err) unless err.nil? || err == ""

    if out.empty?
      $TOOLTIP_OUTPUT << "\t pylint 👍"
    else
      update_errors(out)
    end
  end
  
  # before save
  def run_document_will_save
    err = setup
    TextMate.exit_show_tool_tip(err) unless err.nil?
    
    black
    isort

    print $OUTPUT
  end
  
  # after save
  def run_document_did_save
    err = setup
    TextMate.exit_show_tool_tip(err) unless err.nil?
    
    reset_markers

    pylint
    flake8

    set_markers

    
    if $ERROR_LINES.empty?
      $TOOLTIP_OUTPUT.unshift("Following checks completed:\n")
      $TOOLTIP_OUTPUT << "\nGood to go! ✨ 🍰 ✨"
      result = $TOOLTIP_OUTPUT.join("\n")
    else
      result = ["Found #{$ERROR_LINES.length} error(s)\n"]
      $ERROR_LINES.each do |line, data|
        result << "[line #{line}]"
        data.each do |err|
          result << "\t- #{err[:code]} : #{err[:message]}"
        end
      end
      result = result.join("\n")
    end

    TextMate.exit_show_tool_tip(boxify(result))
  end
end

