require "option_parser"

module SimpleLucky
  VERSION = "0.1.4"

  class App
    private struct SPrintData
      getter cmd : String
      getter desc : String?

      def initialize(@cmd : String, @desc : String?)
      end
    end

    def self.instance
      @@__instance ||= new
      @@__instance.not_nil!
    end

    getter raw_command_string : String = ""
    @namespace_hash = {} of String => NameSpace

    def initialize
    end

    def namespace(name : String | Symbol) : NameSpace
      name_str = name.to_s

      ns = @namespace_hash[name_str]?
      if ns.nil?
        ns = SimpleLucky::NameSpace.new(name_str)
        @namespace_hash[name_str] = ns
      end

      return ns
    end

    private def print_all_task
      target = [] of SPrintData

      your_binary_name = if path = Process.executable_path
                           File.basename(path)
                         else
                           "./your_binary"
                         end

      @namespace_hash.each_value &.print_all_task(target, your_binary_name)

      max_size = target.map(&.cmd.size).max

      target.each do |item|
        if (desc = item.desc) && !desc.empty?
          puts sprintf("%-#{max_size}s    # %s", item.cmd, desc)
        else
          puts item.cmd
        end
      end
    end

    def run
      parse_cmd_option
      parse_task
    end

    private def parse_cmd_option
      OptionParser.parse do |parser|
        parser.banner = "Usage:"
        parser.on("-T", "Show all task") do
          print_all_task
          exit
        end
        parser.on("-h", "--help", "Show this help") do
          puts parser
          exit
        end
        parser.invalid_option do |flag|
          STDERR.puts "ERROR: #{flag} is not a valid option."
          STDERR.puts "\n"
          STDERR.puts parser
          exit(1)
        end
      end
    end

    private def parse_task
      return if ARGV.empty?
      task_cmd = ARGV.first.strip
      # => namespace:taskname
      # => namespace:taskname[...]
      if task_cmd =~ /^(\w+?):(\w+)$/
        namespace_name = $1
        task_name = $2
      elsif task_cmd =~ /^(\w+?):(\w+)\[(.*?)\]$/
        namespace_name = $1
        task_name = $2
        task_args = $3.split(",").map(&.strip).select { |v| !v.empty? }
      else
        raise "unknown command: #{task_cmd}"
      end

      ns = @namespace_hash[namespace_name]?
      raise "unknown namespace: #{namespace_name}" if ns.nil?

      task = ns.task_hash[task_name]?
      raise "unknown task: #{task_name}" if task.nil?

      @raw_command_string = task_cmd

      task.exec(task_args)
    end
  end

  class Task
    alias TaskBlockArgType = Hash(String | Symbol, String)

    getter desc : String?
    getter name : String

    @args = [] of String | Symbol
    @block : Proc(self, TaskBlockArgType, Nil)

    @str_to_symbol_hash = {} of String => Symbol

    def initialize(@desc, @name, *args, &@block : self, Task::TaskBlockArgType ->)
      args.each do |arg_name|
        @args << arg_name

        @str_to_symbol_hash[arg_name.to_s] = arg_name if arg_name.is_a?(Symbol)
      end
    end

    def print_task(target, your_binary_name, namespace)
      main_desc = "#{your_binary_name} #{namespace.name}:#{@name}"
      main_desc = "#{main_desc}[#{@args.join(",")}]" unless @args.empty?

      target << typeof(target[0]).new(main_desc, @desc)
    end

    def exec(task_args : Array(String)?)
      final_args = {} of String | Symbol => String

      if task_args
        arg_name_array = @args.dup
        common_params = [] of String

        # => 1、先分配 hash 关键字参数
        task_args.each do |arg_value|
          kv = arg_value.split(":").map(&.strip)
          if kv.size > 2
            raise "invalid command argument: #{arg_value}"
          elsif kv.size == 2
            str_name = kv[0]
            arg_name = @str_to_symbol_hash[str_name]? || str_name

            if arg_name_array.delete(arg_name)
              final_args[arg_name] = kv[1]
            else
              raise "invalid command argument: #{arg_value}"
            end
          else
            common_params << arg_value
          end
        end

        # => 2、再分配普通参数
        common_params.each do |arg_value|
          arg_name = arg_name_array.shift?
          raise "redundant command argument: #{arg_value}" if arg_name.nil?
          final_args[arg_name] = arg_value
        end
      end

      @block.call(self, final_args)
    end
  end

  class NameSpace
    getter name : String
    getter task_hash = {} of String => Task

    @description_indent = [] of String

    def initialize(@name)
    end

    def desc(description)
      @description_indent << description
    end

    def task(task_name : String | Symbol, *args, &block : Task, Task::TaskBlockArgType ->)
      name_str = task_name.to_s
      @task_hash[name_str] = Task.new(@description_indent.pop?, name_str, *args, &block)
    end

    def print_all_task(target, your_binary_name)
      @task_hash.each_value &.print_task(target, your_binary_name, self)
    end
  end

  def self.run
    App.instance.run
  end
end

def namespace(name : String | Symbol)
  ns = SimpleLucky::App.instance.namespace(name)
  with ns yield ns
end
