module Widget
  class Base
    # TODO: Way of enforcing color limits...
    BLACK       = { r: 0,    g: 0,    b: 0    }.freeze
    DARK_GRAY   = { r: 0x0F, g: 0x0F, b: 0x0F }.freeze
    LIGHT_GRAY  = { r: 0x27, g: 0x27, b: 0x27 }.freeze
    WHITE       = { r: 0x3F, g: 0x3F, b: 0x3F }.freeze

    attr_reader :value, :x, :y, :width, :height
    attr_accessor :on, :off, :down

    # TODO: Use `Vector2` for position/size...
    def initialize(launchpad:, x: nil, y: nil, position: nil, width:, height:, on:, off:, down:, value:)
      @x          = x
      @y          = y
      @position   = position
      @width      = width
      @height     = height
      @on         = BLACK.merge(on)
      @off        = BLACK.merge(off)
      @down       = BLACK.merge(down)
      @launchpad  = launchpad
      @value      = value
      @pressed    = {}

      if @x
        @launchpad.response_to(:grid, :both, x: (@x..(@x + max_x)), y: (@y..(@y + max_y))) do |inter, action|
          handle_grid_response(inter, action)
        end
      else
        @launchpad.response_to(@position, :both) do |inter, action|
          handle_command_response(inter, action)
        end
      end
    end

    def update(value, render_now = true)
      @value = value
      @value = max_v if max_v && @value && @value > max_v
      render if render_now
    end

    def render
      @pressed.map do |idx, state|
        next unless state
        if @x
          xx, yy = coords_for(idx: idx)
          change_grid(x: xx, y: yy, color: down)
        else
          change_command(position: @position, color: down)
        end
      end
    end

    def blank
      if @x
        (0..max_x).each do |xx|
          (0..max_y).each do |yy|
            change_grid(x: xx, y: yy, color: BLACK)
          end
        end
      else
        change_command(position: @position, color: BLACK)
      end
    end

  protected

    attr_reader :launchpad

    def handle_grid_response(inter, action)
      guard_call("#{self.class.name}(#{@x},#{@y})") do
        xx  = action[:x] - @x
        yy  = action[:y] - @y
        idx = index_for(x: xx, y: yy)
        if action[:state] == :down
          @pressed[idx] = true
          on_down(x: xx, y: yy)
        else
          @pressed.delete(idx) if @pressed.key?(idx)
          on_up(x: xx, y: yy)
        end
      end
    end

    def handle_command_response(inter, action)
      guard_call("#{self.class.name}(#{@position})") do
        if action[:state] == :down
          @pressed[@position] = true
          on_down(position: @position)
        else
          @pressed.delete(@position) if @pressed.key?(@position)
          on_up(position: @position)
        end
      end
    end
    def index_for(x:, y:); (y * width) + x; end
    def coords_for(idx:); [idx / width, idx % width]; end

    # Defaults that you may want to override:
    def max_v
      if @x
        @max_v ||= (height * width) - 1
      else
        1
      end
    end

    def on_down(x: nil, y: nil, position: nil)
      if @x
        change_grid(x: x, y: y, color: down)
      else
        change_command(position: position, color: down)
      end
    end

    def on_up(x: nil, y: nil, position: nil); render; end

    # Internal utilities for you to use:
    def change_grid(x:, y:, color:)
      return if (x > max_x) || (x < 0)
      return if (y > max_y) || (y < 0)
      launchpad.device.change_grid(x + @x, y + @y, color[:r], color[:g], color[:b])
    end

    def change_command(position:, color:)
      launchpad.device.change_command(@position, color[:r], color[:g], color[:b])
    end

    def max_y; @max_y ||= height - 1; end
    def max_x; @max_x ||= width - 1; end
  end
end
