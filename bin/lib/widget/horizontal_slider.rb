module Widget
  # Class to represent a slider-style control on a Novation Launchpad.
  class HorizontalSlider < Base
    attr_accessor :on_change

    def initialize(launchpad:, x:, y:, width:, on:, off:, down:, on_change: nil, value: 0)
      super(launchpad: launchpad, x: x, y: y, width: width, height: 1, on: on, off: off, down: down, value: value)
      @on_change = on_change
    end

    def render
      (0..max_v).each do |xx|
        change_grid(x: xx, y: 0, color: (value >= xx) ? on : off)
      end
      super
    end

  protected

    def on_down(x:, y:)
      @value = x
      super(x: x, y: y)
      on_change.call(value) if on_change
    end
  end
end
