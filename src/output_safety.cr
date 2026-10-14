# Output safety (SafeBuffer analog).
#
# Crystal's String cannot be subclassed, so a safe string is a thin
# wrapper type instead. `<%= %>` in compiled templates appends String
# escaped and SafeString raw — same contract as Rails ERB.

module ERB
  class SafeString
    getter raw : String

    def initialize(@raw : String)
    end

    def html_safe? : Bool
      true
    end

    def to_s : String
      @raw
    end

    def to_s(io : IO) : Nil
      io << @raw
    end

    def +(other : SafeString | String) : SafeString
      SafeString.new(@raw + other.to_s)
    end
  end
end

class String
  def html_safe : ERB::SafeString
    ERB::SafeString.new(self)
  end

  def html_safe? : Bool
    false
  end
end
