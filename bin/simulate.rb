#!/usr/bin/env ruby

# TODO: Make node structure more soft-configurable.

# TODO: Run update across nodes from back to front for simulation rather than
# TODO: relying on a call-chain.  This should make it easy to eliminate the
# TODO: `yield` usage and avoid associated allocations.

# TODO: Journal debug information to a log file, and have a separate tool to
# TODO: read that and produce PNGs.

# TODO: Journal timing info about light updates (and transition!), and use that
# TODO: to produce an "as-rendered" debug output.

# TODO: Deeper memory profiling to ensure this process can run for hours.

# TODO: When we integrate input handling and become stateful, journal state to
# TODO: a file that's read on startup so we can survive a restart.

# TODO: Pick four downlights for the dance floor, and treat them as a separate
# TODO: simulation.  Consider how spotlighting and the like will be relevant to
# TODO: them.

# TODO: Node to *clamp* brightness range so we can set the absolute limits at
# TODO: the end of the chain?  Need to consider use-cases more thoroughly.

# TODO: Tools for updating saturation on a group of lights, and a second
# TODO: range-shifting node to allow the photographer some controls.

# https://github.com/taf2/curb/tree/master/bench

#   f = Fiber.new do
#     meth(1) do
#       Fiber.yield
#     end
#   end
#   meth(2) do
#     f.resume
#   end
#   f.resume
#   p Thread.current[:name]

###############################################################################
# Early Initialization/Helpers
###############################################################################
lib = File.expand_path("../../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "flux_hue"

FluxHue.init!("simulate")
FluxHue.use_graph!

# Code loading configuration:
FluxHue.use_hue!(api: true) if env_bool("USE_LIGHTS")
FluxHue.use_launchpad! if env_bool("USE_INPUT")

# Crufty common code:
require "flux_hue/output"

###############################################################################
# Profiling and Debugging
###############################################################################
PROFILE_RUN = ENV["PROFILE_RUN"]
SKIP_GC     = env_bool("SKIP_GC")
DEBUG_FLAGS = Hash[(ENV["DEBUG_NODES"] || "")
                   .split(/\s*,\s*/)
                   .map(&:upcase)
                   .map { |nn| [nn, true] }]
USE_SWEEP   = env_bool("USE_SWEEP")
USE_GRAPH   = env_bool("USE_GRAPH")

###############################################################################
# Shared State Setup
###############################################################################
# TODO: Run all simulations, and use a mixer to blend between them...
num_lights              = CONFIG["main_lights"].length
LIGHTS_FOR_THREADS      = in_groups(CONFIG["main_lights"])
INTERACTION             = Launchpad::Interaction.new(use_threads: false) if defined?(Launchpad)
INT_STATES              = []
NODES                   = {}
PENDING_COMMANDS        = Queue.new
CURRENT_STATE           = {}
STATE_FILENAME          = "tmp/state.tmp"
SKIP_STATE_PERSISTENCE  = [false]
CURRENT_STATE.merge!(YAML.load(File.read(STATE_FILENAME))) if File.exist?(STATE_FILENAME)

def update_state!(key, value)
  old_value = CURRENT_STATE[key]
  return if old_value == value
  CURRENT_STATE[key] = value
  return if SKIP_STATE_PERSISTENCE[0]
  FluxHue.logger.debug { "Persisting control state." }
  File.open(STATE_FILENAME, "w") do |fh|
    fh.write(CURRENT_STATE.to_yaml)
  end
end

###############################################################################
# Simulation Graph Configuration / Setup
###############################################################################
# Root nodes (don't act as modifiers on other nodes' output):
n_cfg           = CONFIG["simulation"]["nodes"]
# NODES["CONST"]  = Nodes::Generators::Const.new(lights: num_lights)
# NODES["WAVE2"]  = Nodes::Generators::Wave2.new(lights: num_lights, speed: n_cfg["wave2"]["speed"])
NODES["PERLIN"] = Nodes::Generators::Perlin.new(lights: num_lights, speed: n_cfg["perlin"]["speed"])
last            = NODES["PERLIN"]

# Transform nodes (act as a chain of modifiers):
c_cfg              = n_cfg["contrast"]
c_func             = Perlin::Curve.const_get(c_cfg["function"].upcase)
NODES["STRETCHED"] = last = Nodes::Transforms::Contrast.new(function:   c_func,
                                                            iterations: c_cfg["iterations"],
                                                            source:     last)
# Create one control group here per "quadrant"...
intensity_cfg = CONFIG["simulation"]["controls"]["intensity"]
LIGHTS_FOR_THREADS.each_with_index do |(_bridge_name, (lights, mask)), idx|
  mask = [false] * num_lights
  lights.map(&:first).each { |ii| mask[ii] = true }

  int_vals    = intensity_cfg["values"]
  last        = Nodes::Transforms::Range.new(initial_min: int_vals[0][0],
                                             initial_max: int_vals[0][1],
                                             source:      last,
                                             mask:        mask)
  NODES["SHIFTED_#{idx}"] = last

  next unless defined?(Launchpad)

  int_colors      = intensity_cfg["colors"]
  pos             = intensity_cfg["positions"][idx]
  int_widget      = Kernel.const_get(intensity_cfg["widget"])
  int_key         = "SHIFTED_#{idx}"
  INT_STATES[idx] = int_widget.new(launchpad: INTERACTION,
                                   x:         pos[0],
                                   y:         pos[1],
                                   size:      intensity_cfg["size"],
                                   on:        int_colors["on"],
                                   off:       int_colors["off"],
                                   down:      int_colors["down"],
                                   on_change: proc do |val|
                                     ival = int_vals[val]
                                     FluxHue.logger.info { "Intensity[#{idx},#{val}]: #{ival}" }
                                     NODES[int_key].set_range(ival[0], ival[1])
                                     update_state!(int_key, val)
                                   end)
end

SAT_STATES = []
if defined?(Launchpad)
  sat_cfg     = CONFIG["simulation"]["controls"]["saturation"]
  sat_len     = sat_cfg["transition"]
  sat_colors  = sat_cfg["colors"]
  sat_vals    = sat_cfg["values"]
  sat_grps    = sat_cfg["groups"]
  sat_widget  = Kernel.const_get(sat_cfg["widget"])
  sat_cfg["positions"].each_with_index do |(xx, yy), idx|
    sat_grp_info  = sat_grps[idx]
    sat_bridge    = CONFIG["bridges"][sat_grp_info[0]]
    sat_group     = sat_grp_info[1]
    sat_key       = "SAT_STATES[#{idx}]"
    SAT_STATES << sat_widget.new(launchpad: INTERACTION,
                                 x:         xx,
                                 y:         yy,
                                 size:      sat_cfg["size"],
                                 on:        sat_colors["on"],
                                 off:       sat_colors["off"],
                                 down:      sat_colors["down"],
                                 on_change: proc do |val|
                                   ival = sat_vals[val]
                                   FluxHue.logger.info { "Saturation[#{idx},#{val}]: #{ival}" }
                                   data = with_transition_time({ "sat" => ival }, sat_len)
                                   req  = { method:   :put,
                                            url:      hue_group_endpoint(sat_bridge, sat_group),
                                            put_data: Oj.dump(data) }.merge(EASY_OPTIONS)
                                   PENDING_COMMANDS << req
                                   update_state!(sat_key, val)
                                 end)
  end
end

last = NODES["SPOTLIT"] = Nodes::Transforms::Spotlight.new(source: last)
FINAL_RESULT            = last # The end node that will be rendered to the lights.
sl_cfg                  = CONFIG["simulation"]["controls"]["spotlighting"]
sl_colors               = sl_cfg["colors"]
sl_map_raw              = sl_cfg["mappings"]
sl_pos                  = sl_map_raw.flatten
sl_key                  = "SPOTLIT"
if defined?(Launchpad)
  SL_STATE = Widgets::RadioGroup.new(launchpad:   INTERACTION,
                                     x:           sl_cfg["x"],
                                     y:           sl_cfg["y"],
                                     size:        [sl_map_raw.map(&:length).sort[-1],
                                                   sl_map_raw.length],
                                     on:          sl_colors["on"],
                                     off:         sl_colors["off"],
                                     down:        sl_colors["down"],
                                     on_select:   proc do |x|
                                       FluxHue.logger.info { "Spotlighting ##{sl_pos[x]}" }
                                       NODES[sl_key].spotlight(sl_pos[x])
                                       update_state!(sl_key, x)
                                     end,
                                     on_deselect: proc do
                                       FluxHue.logger.info { "Spotlighting Off" }
                                       NODES["SPOTLIT"].clear!
                                       update_state!(sl_key, nil)
                                     end)
end

NODES.each do |name, node|
  node.debug = DEBUG_FLAGS[name]
end

###############################################################################
# Operational Configuration
###############################################################################
ITERATIONS                = env_int("ITERATIONS", true) || 0
TIME_TO_DIE               = [false]
Thread.abort_on_exception = false

###############################################################################
# Profiling Support
###############################################################################
if defined?(Launchpad)
  # TODO: Make this optional.
  e_cfg = CONFIG["simulation"]["controls"]["exit"]
  EXIT_BUTTON = Widgets::Button.new(launchpad: INTERACTION,
                                    position:  e_cfg["position"].to_sym,
                                    color:     e_cfg["colors"]["color"],
                                    down:      e_cfg["colors"]["down"],
                                    on_press:  lambda do |value|
                                      return unless value != 0
                                      FluxHue.logger.unknown { "Ending simulation." }
                                      TIME_TO_DIE[0] = true
                                    end)
end

def start_ruby_prof!
  return unless PROFILE_RUN == "ruby-prof"

  FluxHue.logger.unknown { "Enabling ruby-prof, be careful!" }
  require "ruby-prof"
  RubyProf.measure_mode = RubyProf.const_get(ENV.fetch("RUBY_PROF_MODE").upcase)
  RubyProf.start
end

def stop_ruby_prof!
  return unless PROFILE_RUN == "ruby-prof"

  result  = RubyProf.stop
  printer = RubyProf::CallStackPrinter.new(result)
  File.open("tmp/results.html", "w") do |fh|
    printer.print(fh)
  end
end

###############################################################################
# Main Simulation
###############################################################################
def announce_iteration_config(iters)
  if iters > 0
    FluxHue.logger.unknown { "Running for #{iters} iterations." }
  else
    FluxHue.logger.unknown { "Running until we're killed.  Send SIGHUP to terminate with stats." }
  end
end

def clear_board!
  return unless defined?(Launchpad)

  INT_STATES.map(&:blank)
  sleep 0.01 # 88 updates/sec input limit!
  SAT_STATES.map(&:blank)
  sleep 0.01 # 88 updates/sec input limit!
  SL_STATE.blank
  sleep 0.01
  EXIT_BUTTON.blank
end

def any_in_state(threads, state)
  threads = Array(threads)
  threads.find { |th| th.status != state }
end

def wait_for(threads, state)
  threads = Array(threads)
  sleep 0.01 while any_in_state(threads, state)
end

def main
  announce_iteration_config(ITERATIONS)

  global_results = Results.new

  if defined?(Launchpad)
    input_thread = Thread.new do
      guard_call("Input Handler Setup") do
        Thread.stop

        SKIP_STATE_PERSISTENCE[0] = true
        INT_STATES.each_with_index do |ctrl, idx|
          ctrl.update(CURRENT_STATE.fetch("SHIFTED_#{idx}", 0))
        end
        SAT_STATES.each_with_index do |ctrl, idx|
          ctrl.update(CURRENT_STATE.fetch("SAT_STATES[#{idx}]", ctrl.max_v))
        end
        SL_STATE.update(CURRENT_STATE.fetch("SPOTLIT", nil))
        EXIT_BUTTON.update(false)
        SKIP_STATE_PERSISTENCE[0] = false

        # ... and of course we don't want to sleep on this loop, or `join` the
        # thread for the same reason.
        INTERACTION.start
      end
    end
  end

  if USE_GRAPH
    sim_thread = Thread.new do
      guard_call("Base Simulation") do
        Thread.stop

        loop do
          t = Time.now.to_f
          FINAL_RESULT.update(t)
          elapsed = Time.now.to_f - t
          # Try to adhere to a specific update frequency...
          sleep Node::FRAME_PERIOD - elapsed if elapsed < Node::FRAME_PERIOD
        end
      end
    end
  end

  if defined?(LazyRequestConfig) && USE_SWEEP
    # TODO: Make this terminate after main simulation threads have all stopped.
    sweep_thread = Thread.new do
      hues        = CONFIG["simulation"]["sweep"]["values"]
      sweep_len   = CONFIG["simulation"]["sweep"]["length"]

      guard_call("Sweeper") do
        Thread.stop

        loop do
          before_time = Time.now.to_f
          idx         = ((before_time / sweep_len) % hues.length).floor
          data        = with_transition_time({ "hue" => hues[idx] }, sweep_len)
          # TODO: Hoist the hash into something reusable above...
          CONFIG["bridges"].each do |(_name, config)|
            PENDING_COMMANDS << { method:   :put,
                                  url:      hue_group_endpoint(config, 0),
                                  put_data: Oj.dump(data) }.merge(EASY_OPTIONS)
          end

          elapsed = Time.now.to_f - before_time
          sleep sweep_len - elapsed if elapsed < sweep_len
        end
      end
    end
  end

  if defined?(LazyRequestConfig)
    transition  = CONFIG["simulation"]["transition"]
    threads     = LIGHTS_FOR_THREADS.map do |(bridge_name, (lights, _mask))|
      Thread.new do
        guard_call(bridge_name) do
          config    = CONFIG["bridges"][bridge_name]
          results   = Results.new
          iterator  = (ITERATIONS > 0) ? ITERATIONS.times : loop

          FluxHue.logger.unknown do
            light_list = lights.map(&:first).join(", ")
            "#{bridge_name}: Thread set to handle #{lights.count} lights (#{light_list})."
          end

          Thread.stop

          requests = lights
                     .map do |(idx, lid)|
                       url = hue_light_endpoint(config, lid)
                       # TODO: Recycle this hash...
                       LazyRequestConfig.new(FluxHue.logger, config, url, results, debug: DEBUG_FLAGS["OUTPUT"]) do
                         data = { "bri" => (FINAL_RESULT[idx] * 254).to_i }
                         with_transition_time(data, transition)
                       end
                     end

          iterator.each do
            # TODO: Still need this dup?
            Curl::Multi.http(requests.dup, MULTI_OPTIONS) do
            end

            global_results.add_from(results)
            results.clear!
          end
        end
      end
    end

    threads << Thread.new do
      guard_call("Command Queue") do
        loop do
          sleep 0.1 while PENDING_COMMANDS.empty?

          # TODO: Gather stats about success/failure...
          # results     = Results.new
          # global_results.add_from(results)
          # results.clear!

          requests = []
          requests << PENDING_COMMANDS.pop until PENDING_COMMANDS.empty?
          next if requests.length == 0
          FluxHue.logger.debug { "Processing #{requests.length} pending commands." }
          Curl::Multi.http(requests, MULTI_OPTIONS) do |easy|
            FluxHue.logger.debug do
              "Processed command: #{easy.url} => #{easy.response_code}; #{easy.body}"
            end
          end
        end
      end
    end
  else
    threads = []
  end

  # Wait for threads to finish initializing...
  FINAL_RESULT.update(Time.now.to_f)
  wait_for(input_thread, "sleep") if defined?(Launchpad)
  wait_for(sim_thread, "sleep") if USE_GRAPH
  wait_for(sweep_thread, "sleep") if defined?(LazyRequestConfig) && USE_SWEEP
  wait_for(threads, "sleep") if defined?(LazyRequestConfig)
  if SKIP_GC
    FluxHue.logger.unknown { "Disabling garbage collection!  BE CAREFUL!" }
    GC.disable
  end
  FluxHue.logger.debug { "Threads are ready to go, waking them up." }
  global_results.begin!
  start_ruby_prof!
  sim_thread.run if USE_GRAPH
  sweep_thread.run if defined?(LazyRequestConfig) && USE_SWEEP
  threads.each(&:run) if defined?(LazyRequestConfig)
  input_thread.run if defined?(Launchpad)

  trap("INT") do
    TIME_TO_DIE[0] = true
    puts
  end

  loop do
    break if TIME_TO_DIE[0]
    break if defined?(LazyRequestConfig) && !any_in_state(threads, false)
    sleep 0.1
  end

  threads.each(&:terminate) if defined?(LazyRequestConfig)
  sweep_thread.terminate if defined?(LazyRequestConfig) && USE_SWEEP
  sim_thread.terminate if USE_GRAPH
  input_thread.terminate if defined?(Launchpad)
  sleep 0.1

  global_results.done!
  print_results(global_results)
  clear_board!

  stop_ruby_prof!
  index = 0
  NODES.each do |name, node|
    next unless DEBUG_FLAGS[name]
    node.snapshot_to!("tmp/%02d_%s.png" % [index, name.downcase])
    index += 1
  end

  return unless DEBUG_FLAGS["OUTPUT"]
  File.open("tmp/output.raw", "w") do |fh|
    fh.write(LazyRequestConfig::GLOBAL_HISTORY.join("\n"))
    fh.write("\n")
  end
end

###############################################################################
# Launcher
###############################################################################
if PROFILE_RUN == "memory_profiler"
  FluxHue.logger.unknown { "Enabling memory_profiler, be careful!" }
  require "memory_profiler"
  report = MemoryProfiler.report do
    main
    FluxHue.logger.unknown { "Preparing MemoryProfiler report." }
  end
  FluxHue.logger.unknown { "Dumping MemoryProfiler report." }
  # TODO: Dump this to a file...
  report.pretty_print
else
  main
end
