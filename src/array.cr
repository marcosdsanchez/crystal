# An Array is an ordered, integer-indexed collection of objects of type T.
#
# Array indexing starts at 0. A negative index is assumed to be
# relative to the end of the array: -1 indicates the last element,
# -2 is the next to last element, and so on.
#
# An Array can be created using the usual `new` method (several are provided), or with an array literal:
#
# ```
# Array(Int32).new  # => []
# [1, 2, 3]         # Array(Int32)
# [1, "hello", 'x'] # Array(Int32 | String | Char)
# ```
#
# An Array can have mixed types, meaning T will be a union of types, but these are determined
# when the array is created, either by specifying T or by using an array literal. In the latter
# case, T will be set to the union of the array literal elements' types.
#
# When creating an empty array you must always specify T:
#
# ```
# [] of Int32 # same as Array(Int32)
# []          # syntax error
# ```
#
# An Array is implemented using an internal buffer of some capacity
# and is reallocated when elements are pushed to it when more capacity
# is needed. This is normally known as a [dynamic array](http://en.wikipedia.org/wiki/Dynamic_array).
#
# You can use a special array literal syntax with other types too, as long as they define an argless
# `new` method and a `<<` method. `Set` is one such type:
#
# ```
# set = Set{1, 2, 3} # => [1, 2, 3]
# set.class          # => Set(Int32)
# ```
#
# The above is the same as this:
#
# ```
# set = Set(typeof(1, 2, 3)).new
# set << 1
# set << 2
# set << 3
# ```
class Array(T)
  include Enumerable(T)
  include Iterable
  include Comparable(Array)

  # Returns the number of elements in the array.
  #
  # ```
  # [:foo, :bar].size # => 2
  # ```
  getter size
  @size : Int32
  @capacity : Int32

  # Creates a new empty Array.
  def initialize
    @size = 0
    @capacity = 0
    @buffer = Pointer(T).null
  end

  # Creates a new empty Array backed by a buffer that is initially
  # `initial_capacity` big.
  #
  # The *initial_capacity* is useful to avoid unnecessary reallocations
  # of the internal buffer in case of growth. If you have an estimate
  # of the maximum number of elements an array will hold, the array should
  # be initialized with that capacity for improved performance.
  #
  # ```
  # ary = Array(Int32).new(5)
  # ary.size # => 0
  # ```
  def initialize(initial_capacity : Int)
    if initial_capacity < 0
      raise ArgumentError.new("negative array size: #{initial_capacity}")
    end

    @size = 0
    @capacity = initial_capacity.to_i
    if initial_capacity == 0
      @buffer = Pointer(T).null
    else
      @buffer = Pointer(T).malloc(initial_capacity)
    end
  end

  # Creates a new Array of the given *size* filled with the same *value* in each position.
  #
  # ```
  # Array.new(3, 'a') # => ['a', 'a', 'a']
  #
  # ary = Array.new(3, [1])
  # puts ary # => [[1], [1], [1]]
  # ary[0][0] = 2
  # puts ary # => [[2], [2], [2]]
  # ```
  def initialize(size : Int, value : T)
    if size < 0
      raise ArgumentError.new("negative array size: #{size}")
    end

    @size = size.to_i
    @capacity = size.to_i

    if size == 0
      @buffer = Pointer(T).null
    else
      @buffer = Pointer(T).malloc(size, value)
    end
  end

  # Creates a new Array of the given *size* and invokes the given block once for each index of `self`,
  # assigning the block's value in that index.
  #
  # ```
  # Array.new(3) { |i| (i + 1) ** 2 } # => [1, 4, 9]
  #
  # ary = Array.new(3) { [1] }
  # puts ary # => [[1], [1], [1]]
  # ary[0][0] = 2
  # puts ary # => [[2], [1], [1]]
  # ```
  def self.new(size : Int, &block : Int32 -> T)
    Array(T).build(size) do |buffer|
      size.times do |i|
        buffer[i] = yield i
      end
      size
    end
  end

  # Creates a new Array, allocating an internal buffer with the given capacity,
  # and yielding that buffer. The given block must return the desired size of the array.
  #
  # This method is **unsafe**, but is usually used to initialize the buffer
  # by passing it to a C function.
  #
  # ```
  # Array.build(3) do |buffer|
  #   LibSome.fill_buffer_and_return_number_of_elements_filled(buffer)
  # end
  # ```
  def self.build(capacity : Int)
    ary = Array(T).new(capacity)
    ary.size = (yield ary.to_unsafe).to_i
    ary
  end

  # Equality. Returns *true* if each element in `self` is equal to each
  # corresponding element in *other*.
  #
  # ```
  # ary = [1, 2, 3]
  # ary == [1, 2, 3] # => true
  # ary == [2, 3]    # => false
  # ```
  def ==(other : Array)
    equals?(other) { |x, y| x == y }
  end

  # :nodoc:
  def ==(other)
    false
  end

  # Combined comparison operator. Returns *0* if `self` equals *other*, *1* if
  # `self` is greater than *other* and *-1* if `self` is smaller than *other*.
  #
  # It compares the elements of both arrays in the same position using the
  # `<=>` operator.  As soon as one of such comparisons returns a non-zero
  # value, that result is the return value of the comparison.
  #
  # If all elements are equal, the comparison is based on the size of the arrays.
  #
  # ```
  # [8] <=> [1, 2, 3] # => 1
  # [2] <=> [4, 2, 3] # => -1
  # [1, 2] <=> [1, 2] # => 0
  # ```
  def <=>(other : Array)
    min_size = Math.min(size, other.size)
    0.upto(min_size - 1) do |i|
      n = @buffer[i] <=> other.to_unsafe[i]
      return n if n != 0
    end
    size <=> other.size
  end

  # Set intersection: returns a new Array containing elements common to `self`
  # and *other*, excluding any duplicates. The order is preserved from `self`.
  #
  # ```
  # [1, 1, 3, 5] & [1, 2, 3]               # => [ 1, 3 ]
  # ['a', 'b', 'b', 'z'] & ['a', 'b', 'c'] # => [ 'a', 'b' ]
  # ```
  #
  # See also: `#uniq`.
  def &(other : Array(U))
    return Array(T).new if self.empty? || other.empty?

    hash = other.to_lookup_hash
    hash_size = hash.size
    Array(T).build(Math.min(size, other.size)) do |buffer|
      i = 0
      each do |obj|
        hash.delete(obj)
        new_hash_size = hash.size
        if hash_size != new_hash_size
          hash_size = new_hash_size
          buffer[i] = obj
          i += 1
        end
      end
      i
    end
  end

  # Set union: returns a new Array by joining `self` with *other*, excluding
  # any duplicates, and preserving the order from `self`.
  #
  # ```
  # ["a", "b", "c"] | ["c", "d", "a"] # => [ "a", "b", "c", "d" ]
  # ```
  #
  # See also: `#uniq`.
  def |(other : Array(U))
    Array(T | U).build(size + other.size) do |buffer|
      hash = Hash(T, Bool).new
      i = 0
      each do |obj|
        unless hash.has_key?(obj)
          buffer[i] = obj
          hash[obj] = true
          i += 1
        end
      end
      other.each do |obj|
        unless hash.has_key?(obj)
          buffer[i] = obj
          hash[obj] = true
          i += 1
        end
      end
      i
    end
  end

  # Concatenation. Returns a new Array built by concatenating `self` and *other*.
  # The type of the new array is the union of the types of both the original arrays.
  #
  # ```
  # [1, 2] + ["a"]  # => [1,2,"a"] of (Int32 | String)
  # [1, 2] + [2, 3] # => [1,2,2,3]
  # ```
  def +(other : Array(U))
    new_size = size + other.size
    Array(T | U).build(new_size) do |buffer|
      buffer.copy_from(@buffer, size)
      (buffer + size).copy_from(other.to_unsafe, other.size)
      new_size
    end
  end

  # Difference. Returns a new Array that is a copy of `self`, removing any items
  # that appear in *other*. The order of `self` is preserved.
  #
  # ```
  # [1, 2, 3] - [2, 1] # => [3]
  # ```
  def -(other : Array(U))
    ary = Array(T).new(Math.max(size - other.size, 0))
    hash = other.to_lookup_hash
    each do |obj|
      ary << obj unless hash.has_key?(obj)
    end
    ary
  end

  # Repetition: Returns a new Array built by concatenating *times* copies of `self`.
  #
  # ```
  # ["a", "b", "c"] * 2 # => [ "a", "b", "c", "a", "b", "c" ]
  # ```
  def *(times : Int)
    ary = Array(T).new(size * times)
    times.times do
      ary.concat(self)
    end
    ary
  end

  # Append. Alias for `push`.
  #
  # ```
  # a = [1, 2]
  # a << 3 # => [1,2,3]
  # ```
  def <<(value : T)
    push(value)
  end

  # Returns the element at the given index.
  #
  # Negative indices can be used to start counting from the end of the array.
  # Raises `IndexError` if trying to access an element outside the array's range.
  #
  # ```
  # ary = ['a', 'b', 'c']
  # ary[0]  # => 'a'
  # ary[2]  # => 'c'
  # ary[-1] # => 'c'
  # ary[-2] # => 'b'
  #
  # ary[3]  # raises IndexError
  # ary[-4] # raises IndexError
  # ```
  @[AlwaysInline]
  def [](index : Int)
    at(index)
  end

  # Returns the element at the given index.
  #
  # Negative indices can be used to start counting from the end of the array.
  # Returns `nil` if trying to access an element outside the array's range.
  #
  # ```
  # ary = ['a', 'b', 'c']
  # ary[0]?  # => 'a'
  # ary[2]?  # => 'c'
  # ary[-1]? # => 'c'
  # ary[-2]? # => 'b'
  #
  # ary[3]?  # nil
  # ary[-4]? # nil
  # ```
  @[AlwaysInline]
  def []?(index : Int)
    at(index) { nil }
  end

  # Sets the given value at the given index.
  #
  # Negative indices can be used to start counting from the end of the array.
  # Raises `IndexError` if trying to set an element outside the array's range.
  #
  # ```
  # ary = [1, 2, 3]
  # ary[0] = 5
  # p ary # => [5,2,3]
  #
  # ary[3] = 5 # => IndexError
  # ```
  @[AlwaysInline]
  def []=(index : Int, value : T)
    index = check_index_out_of_bounds index
    @buffer[index] = value
  end

  # Replaces a subrange with a single value. All elements in the range
  # `index...index+count` are removed and replaced by a single element
  # *value*.
  #
  # If *count* is zero, *value* is inserted at *index*.
  #
  # Negative values of *index* count from the end of the array.
  #
  # ```
  # a = [1, 2, 3, 4, 5]
  # a[1, 3] = 6
  # a # => [1, 6, 5]
  #
  # a = [1, 2, 3, 4, 5]
  # a[1, 0] = 6
  # a # => [1, 6, 2, 3, 4, 5]
  # ```
  def []=(index : Int, count : Int, value : T)
    raise ArgumentError.new "negative count: #{count}" if count < 0

    index = check_index_out_of_bounds index
    count = index + count <= size ? count : size - index

    case count
    when 0
      insert index, value
    when 1
      @buffer[index] = value
    else
      diff = count - 1
      (@buffer + index + 1).move_from(@buffer + index + count, size - index - count)
      (@buffer + @size - diff).clear(diff)
      @buffer[index] = value
      @size -= diff
    end

    value
  end

  # Replaces a subrange with a single value.
  #
  # ```
  # a = [1, 2, 3, 4, 5]
  # a[1..3] = 6
  # a # => [1, 6, 5]
  #
  # a = [1, 2, 3, 4, 5]
  # a[1...1] = 6
  # a # => [1, 6, 2, 3, 4, 5]
  # ```
  def []=(range : Range(Int, Int), value : T)
    self[*range_to_index_and_count(range)] = value
  end

  # Replaces a subrange with the elements of the given array.
  #
  # ```
  # a = [1, 2, 3, 4, 5]
  # a[1, 3] = [6, 7, 8]
  # a # => [1, 6, 7, 8, 5]
  #
  # a = [1, 2, 3, 4, 5]
  # a[1, 3] = [6, 7]
  # a # => [1, 6, 7, 5]
  #
  # a = [1, 2, 3, 4, 5]
  # a[1, 3] = [6, 7, 8, 9, 10]
  # a # => [1, 6, 7, 8, 9, 10, 5]
  # ```
  def []=(index : Int, count : Int, values : Array(T))
    raise ArgumentError.new "negative count: #{count}" if count < 0

    index = check_index_out_of_bounds index
    count = index + count <= size ? count : size - index
    diff = values.size - count

    if diff == 0
      # Replace values directly
      (@buffer + index).copy_from(values.to_unsafe, values.size)
    elsif diff < 0
      # Need to shrink
      diff = -diff
      (@buffer + index).copy_from(values.to_unsafe, values.size)
      (@buffer + index + values.size).move_from(@buffer + index + count, size - index - count)
      (@buffer + @size - diff).clear(diff)
      @size -= diff
    else
      # Need to grow
      resize_to_capacity(Math.pw2ceil(@size + diff))
      (@buffer + index + values.size).move_from(@buffer + index + count, size - index - count)
      (@buffer + index).copy_from(values.to_unsafe, values.size)
      @size += diff
    end

    values
  end

  # Replaces a subrange with the elements of the given array.
  #
  # ```
  # a = [1, 2, 3, 4, 5]
  # a[1..3] = [6, 7, 8]
  # a # => [1, 6, 7, 8, 5]
  #
  # a = [1, 2, 3, 4, 5]
  # a[1..3] = [6, 7]
  # a # => [1, 6, 7, 5]
  #
  # a = [1, 2, 3, 4, 5]
  # a[1..3] = [6, 7, 8, 9, 10]
  # a # => [1, 6, 7, 8, 9, 10, 5]
  # ```
  def []=(range : Range(Int, Int), values : Array(T))
    self[*range_to_index_and_count(range)] = values
  end

  # Returns all elements that are within the given range
  #
  # Negative indices count backward from the end of the array (-1 is the last
  # element). Additionally, an empty array is returned when the starting index
  # for an element range is at the end of the array.
  #
  # Raises `IndexError` if the starting index is out of range.
  #
  # ```
  # a = ["a", "b", "c", "d", "e"]
  # a[1..3]    # => ["b", "c", "d"]
  # a[4..7]    # => ["e"]
  # a[6..10]   # => Index Error
  # a[5..10]   # => []
  # a[-2...-1] # => ["d"]
  # ```
  def [](range : Range(Int, Int))
    self[*range_to_index_and_count(range)]
  end

  # Returns count or less (if there aren't enough) elements starting at the
  # given start index.
  #
  # Negative indices count backward from the end of the array (-1 is the last
  # element). Additionally, an empty array is returned when the starting index
  # for an element range is at the end of the array.
  #
  # Raises `IndexError` if the starting index is out of range.
  #
  # ```
  # a = ["a", "b", "c", "d", "e"]
  # a[-3, 3] # => ["c", "d", "e"]
  # a[6, 1]  # => Index Error
  # a[1, 2]  # => ["b", "c"]
  # a[5, 1]  # => []
  # ```
  def [](start : Int, count : Int)
    raise ArgumentError.new "negative count: #{count}" if count < 0

    if start == size
      return Array(T).new
    end

    start += size if start < 0
    raise IndexError.new unless 0 <= start <= size

    if count == 0
      return Array(T).new
    end

    count = Math.min(count, size - start)

    Array(T).build(count) do |buffer|
      buffer.copy_from(@buffer + start, count)
      count
    end
  end

  # Returns the element at the given index, if in bounds,
  # otherwise raises `IndexError`.
  #
  # ```
  # a = [:foo, :bar]
  # a.at(0) # => :foo
  # a.at(2) # => IndexError
  # ```
  @[AlwaysInline]
  def at(index : Int)
    at(index) { raise IndexError.new }
  end

  # Returns the element at the given index, if in bounds,
  # otherwise executes the given block and returns its value.
  #
  # ```
  # a = [:foo, :bar]
  # a.at(0) { :baz } # => :foo
  # a.at(2) { :baz } # => :baz
  # ```
  def at(index : Int)
    index += size if index < 0
    if 0 <= index < size
      @buffer[index]
    else
      yield
    end
  end

  # Returns a tuple populated with the elements at the given indexes.
  # Raises `IndexError` if any index is invalid.
  #
  # ```
  # ["a", "b", "c", "d"].values_at(0, 2) # => {"a", "c"}
  # ```
  def values_at(*indexes : Int)
    indexes.map { |index| self[index] }
  end

  # Removes all elements from self.
  #
  # ```
  # a = ["a", "b", "c", "d", "e"]
  # a.clear # => []
  # ```
  def clear
    @buffer.clear(@size)
    @size = 0
    self
  end

  # Returns a new Array that has `self`'s elements cloned.
  # That is, it returns a deep copy of `self`.
  #
  # Use `#dup` if you want a shallow copy.
  #
  # ```
  # ary = [[1, 2], [3, 4]]
  # ary2 = ary.clone
  # ary[0][0] = 5
  # puts ary  # => [[5, 2], [3, 4]]
  # puts ary2 # => [[1, 2], [3, 4]]
  #
  # ary2 << [7, 8]
  # puts ary  # => [[5, 2], [3, 4]]
  # puts ary2 # => [[1, 2], [3, 4], [7, 8]]
  # ```
  def clone
    Array(T).new(size) { |i| @buffer[i].clone as T }
  end

  # Returns a copy of self with all ` elements removed.
  #
  # ```
  # ["a", nil, "b", nil, "c", nil].compact # => ["a", "b", "c"]
  # ```
  def compact
    compact_map &.itself
  end

  # Removes all ` elements from `self`.
  #
  # ```
  # ary = ["a", nil, "b", nil, "c"]
  # ary.compact!
  # ary # => ["a", "b", "c"]
  # ```
  def compact!
    delete nil
  end

  # Appends the elements of *other* to `self`, and returns `self`.
  #
  # ```
  # ary = ["a", "b"]
  # ary.concat(["c", "d"])
  # ary # => ["a", "b", "c", "d"]
  # ```
  def concat(other : Array)
    other_size = other.size
    new_size = size + other_size
    if new_size > @capacity
      resize_to_capacity(Math.pw2ceil(new_size))
    end

    (@buffer + @size).copy_from(other.to_unsafe, other_size)
    @size += other_size

    self
  end

  # ditto
  def concat(other : Enumerable)
    left_before_resize = @capacity - @size
    len = @size
    buf = @buffer + len
    other.each do |elem|
      if left_before_resize == 0
        double_capacity
        left_before_resize = @capacity - len
        buf = @buffer + len
      end
      buf.value = elem
      buf += 1
      len += 1
      left_before_resize -= 1
    end

    @size = len

    self
  end

  # Removes all items from `self` that are equal to *obj*.
  #
  # ```
  # a = ["a", "b", "b", "b", "c"]
  # a.delete("b")
  # a # => ["a", "c"]
  # ```
  def delete(obj)
    reject! { |e| e == obj } != nil
  end

  # Removes the element at *index*, returning that element.
  # Raises `IndexError` if *index* is out of range.
  #
  # ```
  # a = ["ant", "bat", "cat", "dog"]
  # a.delete_at(2)  # => "cat"
  # a               # => ["ant", "bat", "dog"]
  # a.delete_at(99) # => IndexError
  # ```
  def delete_at(index : Int)
    index = check_index_out_of_bounds index

    elem = @buffer[index]
    (@buffer + index).move_from(@buffer + index + 1, size - index - 1)
    @size -= 1
    (@buffer + @size).clear
    elem
  end

  # Removes all elements within the given *range*.
  # Returns an array of the removed elements with the original order of `self` preserved.
  # Raises `IndexError` if the index is out of range.
  #
  # ```
  # a = ["ant", "bat", "cat", "dog"]
  # a.delete_at(1..2)    # => ["bat", "cat"]
  # a                    # => ["ant", "dog"]
  # a.delete_at(99..100) # => IndexError
  # ```
  def delete_at(range : Range(Int, Int))
    from, size = range_to_index_and_count(range)
    delete_at(from, size)
  end

  # Removes *count* elements from `self` starting at *index*.
  # If the size of `self` is less than *count*, removes values to the end of the array without error.
  # Returns an array of the removed elements with the original order of `self` preserved.
  # Raises `IndexError` if *index* is out of range.
  #
  # ```
  # a = ["ant", "bat", "cat", "dog"]
  # a.delete_at(1, 2)  # => ["bat", "cat"]
  # a                  # => ["ant", "dog"]
  # a.delete_at(99, 1) # => IndexError
  # ```
  def delete_at(index : Int, count : Int)
    val = self[index, count]
    count = index + count <= size ? count : size - index
    (@buffer + index).move_from(@buffer + index + count, size - index - count)
    @size -= count
    (@buffer + @size).clear(count)
    val
  end

  # Returns a new Array that has exactly `self`'s elements.
  # That is, it returns a shallow copy of `self`.
  #
  # Use `#clone` if you want a deep copy.
  #
  # ```
  # ary = [[1, 2], [3, 4]]
  # ary2 = ary.dup
  # ary[0][0] = 5
  # puts ary  # => [[5, 2], [3, 4]]
  # puts ary2 # => [[5, 2], [3, 4]]
  #
  # ary2 << [7, 8]
  # puts ary  # => [[5, 2], [3, 4]]
  # puts ary2 # => [[5, 2], [3, 4], [7, 8]]
  # ```
  def dup
    Array(T).build(@capacity) do |buffer|
      buffer.copy_from(@buffer, size)
      size
    end
  end

  # Calls the given block once for each element in `self`, passing that
  # element as a parameter.
  #
  # ```
  # a = ["a", "b", "c"]
  # a.each { |x| print x, " -- " }
  # ```
  #
  # produces:
  #
  # ```text
  # a -- b -- c --
  # ```
  def each
    each_index do |i|
      yield @buffer[i]
    end
  end

  # Returns an `Iterator` for the elements of `self`.
  #
  # ```
  # a = ["a", "b", "c"]
  # iter = a.each
  # iter.next # => "a"
  # iter.next # => "b"
  # ```
  #
  # The returned iterator keeps a reference to `self`: if the array
  # changes, the returned values of the iterator change as well.
  def each
    ItemIterator.new(self)
  end

  # Calls the given block once for each index in `self`, passing that
  # index as a parameter.
  #
  # ```
  # a = ["a", "b", "c"]
  # a.each_index { |x| print x, " -- " }
  # ```
  #
  # produces:
  #
  # ```text
  # 0 -- 1 -- 2 --
  # ```
  def each_index
    i = 0
    while i < size
      yield i
      i += 1
    end
    self
  end

  # Returns an `Iterator` for each index in `self`.
  #
  # ```
  # a = ["a", "b", "c"]
  # iter = a.each_index
  # iter.next # => 0
  # iter.next # => 1
  # ```
  #
  # The returned iterator keeps a reference to `self`. If the array
  # changes, the returned values of the iterator will change as well.
  def each_index
    IndexIterator.new(self)
  end

  # Returns *true* if `self` is empty, *false* otherwise.
  #
  # ```
  # ([] of Int32).empty? # => true
  # ([1]).empty?         # => false
  # ```
  def empty?
    @size == 0
  end

  # Determines if `self` equals *other* according to a comparison
  # done by the given block.
  #
  # If `self`'s size is the same as *other*'s size, this method yields
  # elements from `self` and *other* in tandem: if the block returns true
  # for all of them, this method returns *true*. Otherwise it returns *false*.
  #
  # ```
  # a = [1, 2, 3]
  # b = ["a", "ab", "abc"]
  # a.equals?(b) { |x, y| x == y.size } # => true
  # a.equals?(b) { |x, y| x == y }      # => false
  # ```
  def equals?(other : Array)
    return false if @size != other.size
    each_with_index do |item, i|
      return false unless yield(item, other[i])
    end
    true
  end

  # Yields each index of `self` to the given block and then assigns
  # the block's value in that position. Returns `self`.
  #
  # ```
  # a = [1, 2, 3, 4]
  # a.fill { |i| i * i } # => [0, 1, 4, 9]
  # ```
  def fill
    each_index { |i| @buffer[i] = yield i }

    self
  end

  # Yields each index of `self`, starting at *from*, to the given block and then assigns
  # the block's value in that position. Returns `self`.
  #
  # Negative values of *from* count from the end of the array.
  #
  # ```
  # a = [1, 2, 3, 4]
  # a.fill(2) { |i| i * i } # => [1, 2, 4, 9]
  # ```
  def fill(from : Int)
    from += size if from < 0

    raise IndexError.new if from >= size

    from.upto(size - 1) { |i| @buffer[i] = yield i }

    self
  end

  # Yields each index of `self`, starting at *from* and just *count* times,
  # to the given block and then assigns the block's value in that position. Returns `self`.
  #
  # Negative values of *from* count from the end of the array.
  #
  # ```
  # a = [1, 2, 3, 4, 5, 6]
  # a.fill(2, 2) { |i| i * i } # => [1, 2, 4, 9, 5, 6]
  # ```
  def fill(from : Int, count : Int)
    return self if count < 0

    from += size if from < 0
    count += size if count < 0

    raise IndexError.new if from >= size || count + from > size

    count += from - 1

    from.upto(count) { |i| @buffer[i] = yield i }

    self
  end

  # Yields each index of `self`, in the given *range*, to the given block and then assigns
  # the block's value in that position. Returns `self`.
  #
  # ```
  # a = [1, 2, 3, 4, 5, 6]
  # a.fill(2..3) { |i| i * i } # => [1, 2, 4, 9, 5, 6]
  # ```
  def fill(range : Range(Int, Int))
    fill(*range_to_index_and_count(range)) do |i|
      yield i
    end
  end

  # Replaces every element in `self` with the given *value*. Returns `self`.
  #
  # ```
  # a = [1, 2, 3]
  # a.fill(9) # => [9, 9, 9]
  # ```
  def fill(value : T)
    fill { value }
  end

  # Replaces every element in `self`, starting at *from*, with the given *value*. Returns `self`.
  #
  # Negative values of *from* count from the end of the array.
  #
  # ```
  # a = [1, 2, 3, 4, 5]
  # a.fill(9, 2) # => [1, 2, 9, 9, 9]
  # ```
  def fill(value : T, from : Int)
    fill(from) { value }
  end

  # Replaces every element in `self`, starting at *from* and only *count* times,
  # with the given *value*. Returns `self`.
  #
  # Negative values of *from* count from the end of the array.
  #
  # ```
  # a = [1, 2, 3, 4, 5]
  # a.fill(9, 2, 2) # => [1, 2, 9, 9, 5]
  # ```
  def fill(value : T, from : Int, count : Int)
    fill(from, count) { value }
  end

  # Replaces every element in *range* with *value*. Returns `self`.
  #
  # Negative values of *from* count from the end of the array.
  #
  # ```
  # a = [1, 2, 3, 4, 5]
  # a.fill(9, 2..3) # => [1, 2, 9, 9, 5]
  # ```
  def fill(value : T, range : Range(Int, Int))
    fill(range) { value }
  end

  # Returns the first element of `self` if it's not empty, or raises `IndexError`.
  #
  # ```
  # ([1, 2, 3]).first   # => 1
  # ([] of Int32).first # => raises IndexError
  # ```
  def first
    first { raise IndexError.new }
  end

  # Returns the first element of `self` if it's not empty, or the given block's value.
  #
  # ```
  # ([1, 2, 3]).first { 4 }   # => 1
  # ([] of Int32).first { 4 } # => 4
  # ```
  def first
    @size == 0 ? yield : @buffer[0]
  end

  # Returns the first element of `self` if it's not empty, or `.
  #
  # ```
  # ([1, 2, 3]).first?   # => 1
  # ([] of Int32).first? # => nil
  # ```
  def first?
    first { nil }
  end

  # Returns a hash code based on `self`'s size and elements.
  #
  # See `Object#hash`.
  def hash
    reduce(31 * @size) do |memo, elem|
      31 * memo + elem.hash
    end
  end

  # Insert *object* before the element at *index* and shifting successive elements, if any.
  # Returns `self`.
  #
  # Negative values of *index* count from the end of the array.
  #
  # ```
  # a = ["a", "b", "c"]
  # a.insert(0, "x")  # => ["x", "a", "b", "c"]
  # a.insert(2, "y")  # => ["x", "a", "y", "b", "c"]
  # a.insert(-1, "z") # => ["x", "a", "y", "b", "c", "z"]
  # ```
  def insert(index : Int, object : T)
    check_needs_resize

    if index < 0
      index += size + 1
    end

    unless 0 <= index <= size
      raise IndexError.new
    end

    (@buffer + index + 1).move_from(@buffer + index, size - index)
    @buffer[index] = object
    @size += 1
    self
  end

  # :nodoc:
  def inspect(io : IO)
    to_s io
  end

  # Returns the last element of `self` if it's not empty, or raises `IndexError`.
  #
  # ```
  # ([1, 2, 3]).last   # => 3
  # ([] of Int32).last # => raises IndexError
  # ```
  def last
    last { raise IndexError.new }
  end

  # Returns the last element of `self` if it's not empty, or the given block's value.
  #
  # ```
  # ([1, 2, 3]).last { 4 }   # => 3
  # ([] of Int32).last { 4 } # => 4
  # ```
  def last
    @size == 0 ? yield : @buffer[@size - 1]
  end

  # Returns the last element of `self` if it's not empty, or `.
  #
  # ```
  # ([1, 2, 3]).last?   # => 1
  # ([] of Int32).last? # => nil
  # ```
  def last?
    last { nil }
  end

  # :nodoc:
  protected def size=(size : Int)
    @size = size.to_i
  end

  # Optimized version of `Enumerable#map`.
  def map(&block : T -> U)
    Array(U).new(size) { |i| yield @buffer[i] }
  end

  # Invokes the given block for each element of `self`, replacing the element
  # with the value returned by the block. Returns `self`.
  #
  # ```
  # a = [1, 2, 3]
  # a.map! { |x| x * x }
  # a # => [1, 4, 9]
  # ```
  def map!
    @buffer.map!(size) { |e| yield e }
    self
  end

  # Modifies `self`, keeping only the elements in the collection for which the
  # passed block returns *true*. Returns ` if no changes were made.
  #
  # See also `Array#select`
  def select!
    reject! { |elem| !yield(elem) }
  end

  # Modifies `self`, deleting the elements in the collection for which the
  # passed block returns *true*. Returns ` if no changes were made.
  #
  # See also `Array#reject`
  def reject!
    i1 = 0
    i2 = 0
    while i1 < @size
      e = @buffer[i1]
      unless yield e
        if i1 != i2
          @buffer[i2] = e
        end
        i2 += 1
      end

      i1 += 1
    end

    if i2 != i1
      count = i1 - i2
      @size -= count
      (@buffer + @size).clear(count)
      self
    else
      nil
    end
  end

  # Optimized version of `Enumerable#map_with_index`.
  def map_with_index(&block : T, Int32 -> U)
    Array(U).new(size) { |i| yield @buffer[i], i }
  end

  # Returns an Array with all possible permutations of *size*.
  #
  #     a = [1, 2, 3]
  #     a.permutations    #=> [[1,2,3],[1,3,2],[2,1,3],[2,3,1],[3,1,2],[3,2,1]]
  #     a.permutations(1) #=> [[1],[2],[3]]
  #     a.permutations(2) #=> [[1,2],[1,3],[2,1],[2,3],[3,1],[3,2]]
  #     a.permutations(3) #=> [[1,2,3],[1,3,2],[2,1,3],[2,3,1],[3,1,2],[3,2,1]]
  #     a.permutations(0) #=> [[]]
  #     a.permutations(4) #=> []
  #
  def permutations(size : Int = self.size)
    ary = [] of Array(T)
    each_permutation(size) do |a|
      ary << a
    end
    ary
  end

  # Yields each possible permutation of *size* of `self`.
  #
  #     a = [1, 2, 3]
  #     sums = [] of Int32
  #     a.each_permutation(2) { |p| sums << p.sum } #=> [1, 2, 3]
  #     sums #=> [3, 4, 3, 5, 4, 5]
  #
  def each_permutation(size : Int = self.size)
    n = self.size
    return self if size > n

    raise ArgumentError.new("size must be positive") if size < 0

    pool = self.dup
    cycles = (n - size + 1..n).to_a.reverse!
    yield pool[0, size]

    while true
      stop = true
      i = size - 1
      while i >= 0
        ci = (cycles[i] -= 1)
        if ci == 0
          e = pool[i]
          (i + 1).upto(n - 1) { |j| pool[j - 1] = pool[j] }
          pool[n - 1] = e
          cycles[i] = n - i
        else
          pool.swap i, -ci
          yield pool[0, size]
          stop = false
          break
        end
        i -= 1
      end

      return self if stop
    end
  end

  # Returns an `Iterator` over each possible permutation of *size* of `self`.
  #
  # ```
  # iter = [1, 2, 3].each_permutation
  # iter.next # => [1, 2, 3]
  # iter.next # => [1, 3, 2]
  # iter.next # => [2, 1, 3]
  # iter.next # => [2, 3, 1]
  # iter.next # => [3, 1, 2]
  # iter.next # => [3, 2, 1]
  # iter.next # => Iterator::Stop
  # ```
  def each_permutation(size : Int = self.size)
    raise ArgumentError.new("size must be positive") if size < 0

    PermutationIterator.new(self, size.to_i)
  end

  def combinations(size : Int = self.size)
    ary = [] of Array(T)
    each_combination(size) do |a|
      ary << a
    end
    ary
  end

  def each_combination(size : Int = self.size)
    n = self.size
    return self if size > n
    raise ArgumentError.new("size must be positive") if size < 0

    copy = self.dup
    pool = self.dup

    indices = (0...size).to_a
    yield pool[0, size]

    while true
      stop = true
      i = size - 1
      while i >= 0
        if indices[i] != i + n - size
          stop = false
          break
        end
        i -= 1
      end

      return self if stop

      indices[i] += 1
      pool[i] = copy[indices[i]]

      (i + 1).upto(size - 1) do |j|
        indices[j] = indices[j - 1] + 1
        pool[j] = copy[indices[j]]
      end

      yield pool[0, size]
    end
  end

  def each_combination(size : Int = self.size)
    raise ArgumentError.new("size must be positive") if size < 0

    CombinationIterator.new(self, size.to_i)
  end

  # Returns a new Array that is a one-dimensional flattening of self (recursively).
  #
  # That is, for every element that is an array, extract its elements into the new array
  #
  # ```
  # s = [1, 2, 3]         # => [1, 2, 3]
  # t = [4, 5, 6, [7, 8]] # => [4, 5, 6, [7, 8]]
  # a = [s, t, 9, 10]     # => [[1, 2, 3], [4, 5, 6, [7, 8]], 9, 10]
  # a.flatten             # => [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  # ```
  def flatten
    FlattenHelper(typeof(FlattenHelper.element_type(self))).flatten(self)
  end

  def repeated_combinations(size : Int = self.size)
    ary = [] of Array(T)
    each_repeated_combination(size) do |a|
      ary << a
    end
    ary
  end

  def each_repeated_combination(size : Int = self.size)
    n = self.size
    return self if size > n && n == 0
    raise ArgumentError.new("size must be positive") if size < 0

    copy = self.dup
    indices = Array.new(size, 0)
    pool = indices.map { |i| copy[i] }

    yield pool[0, size]

    while true
      stop = true

      i = size - 1
      while i >= 0
        if indices[i] != n - 1
          stop = false
          break
        end
        i -= 1
      end
      return self if stop

      ii = indices[i] + 1
      tmp = copy[ii]
      indices.fill(i, size - i) { ii }
      pool.fill(i, size - i) { tmp }

      yield pool[0, size]
    end
  end

  def each_repeated_combination(size : Int = self.size)
    raise ArgumentError.new("size must be positive") if size < 0

    RepeatedCombinationIterator.new(self, size.to_i)
  end

  def self.product(arrays)
    result = [] of Array(typeof(arrays.first.first))
    each_product(arrays) do |product|
      result << product
    end
    result
  end

  def self.product(*arrays : Array)
    product(arrays.to_a)
  end

  def self.each_product(arrays)
    pool = arrays.map &.first
    lens = arrays.map &.size
    return if lens.any? &.==(0)
    n = arrays.size
    indices = Array.new(n, 0)
    yield pool[0, n]

    while true
      i = n - 1
      indices[i] += 1

      while indices[i] >= lens[i]
        indices[i] = 0
        pool[i] = arrays[i][indices[i]]
        i -= 1
        return if i < 0
        indices[i] += 1
      end
      pool[i] = arrays[i][indices[i]]
      yield pool[0, n]
    end
  end

  def self.each_product(*arrays : Array)
    each_product(arrays.to_a) do |result|
      yield result
    end
  end

  def repeated_permutations(size : Int = self.size)
    ary = [] of Array(T)
    each_repeated_permutation(size) do |a|
      ary << a
    end
    ary
  end

  def each_repeated_permutation(size : Int = self.size)
    n = self.size
    return self if size != 0 && n == 0
    raise ArgumentError.new("size must be positive") if size < 0

    if size == 0
      yield([] of T)
    else
      Array.each_product(Array.new(size, self)) { |r| yield r }
    end

    self
  end

  # Removes the last value from `self`, at index *size - 1*.
  # This method returns the removed value.
  # Raises `IndexError` if array is of 0 size.
  #
  # ```
  # a = ["a", "b", "c"]
  # a.pop # => "c"
  # a     # => ["a", "b"]
  # ```
  def pop
    pop { raise IndexError.new }
  end

  def pop
    if @size == 0
      yield
    else
      @size -= 1
      value = @buffer[@size]
      (@buffer + @size).clear
      value
    end
  end

  # Removes the last *n* values from `self`, at index *size - 1*.
  # This method returns an array of the removed values, with the original order preserved.
  #
  # If *n* is greater than the size of `self`, all values will be removed from `self`
  # without raising an error.
  #
  # ```
  # a = ["a", "b", "c"]
  # a.pop(2) # => ["b", "c"]
  # a        # => ["a"]
  #
  # a = ["a", "b", "c"]
  # a.pop(4) # => ["a", "b", "c"]
  # a        # => []
  # ```
  def pop(n : Int)
    if n < 0
      raise ArgumentError.new("can't pop negative count")
    end

    n = Math.min(n, @size)
    ary = Array(T).new(n) { |i| @buffer[@size - n + i] }

    @size -= n
    (@buffer + @size).clear(n)

    ary
  end

  def pop?
    pop { nil }
  end

  def product(ary : Array(U))
    result = Array({T, U}).new(size * ary.size)
    product(ary) do |x, y|
      result << {x, y}
    end
    result
  end

  def product(ary, &block)
    self.each { |a| ary.each { |b| yield a, b } }
  end

  # Append. Pushes one value to the end of `self`, given that the type of the value is *T*
  # (which might be a single type or a union of types).
  # This method returns `self`, so several calls can be chained. See `pop` for the opposite effect.
  #
  # ```
  # a = ["a", "b"]
  # a.push("c") # => ["a", "b", "c"]
  # a.push(1)   # => Errors, because the array only accepts String
  #
  # a = ["a", "b"] of (Int32 | String)
  # a.push("c") # => ["a", "b", "c"]
  # a.push(1)   # => ["a", "b", "c", 1]
  # ```
  def push(value : T)
    check_needs_resize
    @buffer[@size] = value
    @size += 1
    self
  end

  # Append multiple values. The same as `push`, but takes an arbitrary number
  # of values to push into `self`. Returns `self`.
  #
  # ```
  # a = ["a"]
  # a.push(["b", "c"]) # => ["a", "b", "c"]
  # ```
  def push(*values : T)
    new_size = @size + values.size
    resize_to_capacity(Math.pw2ceil(new_size)) if new_size > @capacity
    values.each_with_index do |value, i|
      @buffer[@size + i] = value
    end
    @size = new_size
    self
  end

  def replace(other : Array)
    @size = other.size
    resize_to_capacity(Math.pw2ceil(@size)) if @size > @capacity
    @buffer.copy_from(other.to_unsafe, other.size)
    self
  end

  # Returns an array with all the elements in the collection reversed.
  #
  # ```
  # a = [1, 2, 3]
  # a.reverse # => [3, 2, 1]
  # ```
  def reverse
    Array(T).new(size) { |i| @buffer[size - i - 1] }
  end

  # Reverses in-place all the elements of `self`.
  def reverse!
    i = 0
    j = size - 1
    while i < j
      @buffer.swap i, j
      i += 1
      j -= 1
    end
    self
  end

  # Calls the given block once for each element in `self` in reverse order,
  # passing that element as a parameter.
  #
  # ```
  # a = ["a", "b", "c"]
  # a.reverse_each { |x| print x, " -- " }
  # ```
  #
  # produces:
  #
  # ```text
  # c -- b -- a --
  # ```
  def reverse_each
    (size - 1).downto(0) do |i|
      yield @buffer[i]
    end
    self
  end

  def reverse_each
    ReverseIterator.new(self)
  end

  def rindex(value)
    rindex { |elem| elem == value }
  end

  def rindex
    (size - 1).downto(0) do |i|
      if yield @buffer[i]
        return i
      end
    end
    nil
  end

  def rotate!(n = 1)
    return self if size == 0
    n %= size if n.abs >= size
    n += size if n < 0
    return self if n == 0
    if n <= size / 2
      tmp = self[0..n]
      @buffer.move_from(@buffer + n, size - n)
      (@buffer + size - n).copy_from(tmp.to_unsafe, n)
    else
      tmp = self[n..-1]
      (@buffer + size - n).move_from(@buffer, n)
      @buffer.copy_from(tmp.to_unsafe, size - n)
    end
    self
  end

  def rotate(n = 1)
    return self if size == 0
    n %= size if n.abs >= size
    n += size if n < 0
    return self if n == 0
    res = Array(T).new(size)
    res.to_unsafe.copy_from(@buffer + n, size - n)
    (res.to_unsafe + size - n).copy_from(@buffer, n)
    res.size = size
    res
  end

  # Returns a random element from `self`, using the given *random* number generator.
  # Raises IndexError if `self` is empty.
  #
  # ```
  # a = [1, 2, 3]
  # a.sample                # => 2
  # a.sample                # => 1
  # a.sample(Random.new(1)) # => 3
  # ```
  def sample(random = Random::DEFAULT)
    raise IndexError.new if @size == 0
    @buffer[random.rand(@size)]
  end

  # Returns *n* number of random elements from `self`, using the given *random* number generator.
  # Raises IndexError if `self` is empty.
  #
  # ```
  # a = [1, 2, 3]
  # a.sample(2)                # => [2, 1]
  # a.sample(2, Random.new(1)) # => [1, 3]
  # ```
  def sample(n : Int, random = Random::DEFAULT)
    if n < 0
      raise ArgumentError.new("can't get negative count sample")
    end

    case n
    when 0
      return [] of T
    when 1
      return [sample] of T
    else
      if n >= @size
        return dup.shuffle!
      end

      ary = Array(T).new(n) { |i| @buffer[i] }
      buffer = ary.to_unsafe

      n.upto(@size - 1) do |i|
        j = random.rand(i + 1)
        if j <= n
          buffer[j] = @buffer[i]
        end
      end
      ary.shuffle!(random)

      ary
    end
  end

  # Removes the first value of `self`, at index 0. This method returns the removed value.
  # Raises `IndexError` if array is of 0 size.
  #
  # ```
  # a = ["a", "b", "c"]
  # a.shift # => "a"
  # a       # => ["b", "c"]
  # ```
  def shift
    shift { raise IndexError.new }
  end

  def shift
    if @size == 0
      yield
    else
      value = @buffer[0]
      @size -= 1
      @buffer.move_from(@buffer + 1, @size)
      (@buffer + @size).clear
      value
    end
  end

  # Removes the first *n* values of `self`, starting at index 0.
  # This method returns an array of the removed values.
  #
  # If *n* is greater than the size of `self`, all values will be removed from `self`
  # without raising an error.
  #
  # ```
  # a = ["a", "b", "c"]
  # a.shift # => "a"
  # a       # => ["b", "c"]
  #
  # a = ["a", "b", "c"]
  # a.shift(4) # => ["a", "b", "c"]
  # a          # => []
  # ```
  def shift(n : Int)
    if n < 0
      raise ArgumentError.new("can't shift negative count")
    end

    n = Math.min(n, @size)
    ary = Array(T).new(n) { |i| @buffer[i] }

    @buffer.move_from(@buffer + n, @size - n)
    @size -= n
    (@buffer + @size).clear(n)

    ary
  end

  def shift?
    shift { nil }
  end

  # Returns an array with all the elements in the collection randomized
  # using the given *random* number generator.
  def shuffle(random = Random::DEFAULT)
    dup.shuffle!(random)
  end

  # Modifies `self` by randomizing the order of elements in the collection
  # using the given *random* number generator.  Returns `self`.
  def shuffle!(random = Random::DEFAULT)
    @buffer.shuffle!(size, random)
    self
  end

  # Returns an array with all elements in the collection sorted.
  #
  # ```
  # a = [3, 1, 2]
  # a.sort # => [1, 2, 3]
  # a      # => [3, 1, 2]
  # ```
  #
  # Optionally, a block may be given that must implement a comparison, either with the comparison operator `<=>`
  # or a comparison between *a* and *b*, where a < b yields -1, a == b yields 0, and a > b yields 1.
  def sort
    dup.sort!
  end

  def sort(&block : T, T -> Int32)
    dup.sort! &block
  end

  # Modifies `self` by sorting the elements in the collection.
  #
  # ```
  # a = [3, 1, 2]
  # a.sort!
  # a # => [1, 2, 3]
  # ```
  #
  # Optionally, a block may be given that must implement a comparison, either with the comparison operator `<=>`
  # or a comparison between *a* and *b*, where a < b yields -1, a == b yields 0, and a > b yields 1.
  def sort!
    Array.quicksort!(@buffer, @size)
    self
  end

  def sort!(&block : T, T -> Int32)
    Array.quicksort!(@buffer, @size, block)
    self
  end

  def sort_by(&block : T -> _)
    dup.sort_by! &block
  end

  def sort_by!(&block : T -> _)
    sorted = map { |e| {e, block.call(e)} }.sort! { |x, y| x[1] <=> y[1] }
    @size.times do |i|
      @buffer[i] = sorted.to_unsafe[i][0]
    end
    self
  end

  def swap(index0, index1)
    index0 += size if index0 < 0
    index1 += size if index1 < 0

    unless (0 <= index0 < size) && (0 <= index1 < size)
      raise IndexError.new
    end

    @buffer[index0], @buffer[index1] = @buffer[index1], @buffer[index0]

    self
  end

  def to_a
    self
  end

  def to_s(io : IO)
    executed = exec_recursive(:to_s) do
      io << "["
      join ", ", io, &.inspect(io)
      io << "]"
    end
    io << "[...]" unless executed
  end

  # Returns a pointer to the internal buffer where `self`'s elements are stored.
  #
  # This method is **unsafe** because it returns a pointer, and the pointed might eventually
  # not be that of `self` if the array grows and its internal buffer is reallocated.
  #
  # ```
  # ary = [1, 2, 3]
  # ary.to_unsafe[0] # => 1
  # ```
  def to_unsafe : Pointer(T)
    @buffer
  end

  # Assumes that `self` is an array of arrays and transposes the rows and columns.
  #
  # ```
  # a = [[:a, :b], [:c, :d], [:e, :f]]
  # a.transpose # => [[:a, :c, :e], [:b, :d, :f]]
  # a           # => [[:a, :b], [:c, :d], [:e, :f]]
  # ```
  def transpose
    return Array(Array(typeof(first.first))).new if empty?

    len = at(0).size
    (1...@size).each do |i|
      l = at(i).size
      raise IndexError.new if len != l
    end

    Array(Array(typeof(first.first))).new(len) do |i|
      Array(typeof(first.first)).new(@size) do |j|
        at(j).at(i)
      end
    end
  end

  # Returns a new Array by removing duplicate values in `self`.
  #
  # ```
  # a = ["a", "a", "b", "b", "c"]
  # a.uniq # => ["a", "b", "c"]
  # a      # => [ "a", "a", "b", "b", "c" ]
  # ```
  def uniq
    uniq &.itself
  end

  # Returns a new Array by removing duplicate values in `self`, using the block's
  # value for comparison.
  #
  # ```
  # a = [{"student", "sam"}, {"student", "george"}, {"teacher", "matz"}]
  # a.uniq { |s| s[0] } # => [{"student", "sam"}, {"teacher", "matz"}]
  # a                   # => [{"student", "sam"}, {"student", "george"}, {"teacher", "matz"}]
  # ```
  def uniq(&block : T -> _)
    if size <= 1
      dup
    else
      hash = to_lookup_hash { |elem| yield elem }
      hash.values
    end
  end

  # Removes duplicate elements from `self`. Returns `self`.
  #
  # ```
  # a = ["a", "a", "b", "b", "c"]
  # a.uniq! # => ["a", "b", "c"]
  # a       # => ["a", "b", "c"]
  # ```
  def uniq!
    uniq! &.itself
  end

  # Removes duplicate elements from `self`, using the block's value for comparison. Returns `self`.
  #
  # ```
  # a = [{"student", "sam"}, {"student", "george"}, {"teacher", "matz"}]
  # a.uniq! { |s| s[0] } # => [{"student", "sam"}, {"teacher", "matz"}]
  # a                    # => [{"student", "sam"}, {"teacher", "matz"}]
  # ```
  def uniq!
    if size <= 1
      return self
    end

    hash = to_lookup_hash { |elem| yield elem }
    if size == hash.size
      return self
    end

    old_size = @size
    @size = hash.size
    removed = old_size - @size
    return self if removed == 0

    ptr = @buffer
    hash.each do |k, v|
      ptr.value = v
      ptr += 1
    end

    (@buffer + @size).clear(removed)

    self
  end

  # Prepend. Adds *obj* to the beginning of `self`, given that the type of the value is *T*
  # (which might be a single type or a union of types).
  # This method returns `self`, so several calls can be chained. See `shift` for the opposite effect.
  #
  # ```
  # a = ["a", "b"]
  # a.unshift("c") # => ["c", a", "b"]
  # a.unshift(1)   # => Errors, because the array only accepts String
  #
  # a = ["a", "b"] of (Int32 | String)
  # a.unshift("c") # => ["c", "a", "b"]
  # a.unshift(1)   # => [1, "a", "b", "c"]
  # ```
  def unshift(obj : T)
    insert 0, obj
  end

  # Prepend multiple values. The same as `unshift`, but takes an arbitrary number
  # of values to add to the array. Returns `self`.
  def unshift(*values : T)
    new_size = @size + values.size
    resize_to_capacity(Math.pw2ceil(new_size)) if new_size > @capacity
    move_value = values.size
    @buffer.move_to(@buffer + move_value, @size)

    values.each_with_index do |value, i|
      @buffer[i] = value
    end
    @size = new_size
    self
  end

  def update(index : Int)
    index = check_index_out_of_bounds index
    @buffer[index] = yield @buffer[index]
  end

  def zip(other : Array)
    each_with_index do |elem, i|
      yield elem, other[i]
    end
  end

  def zip(other : Array(U))
    pairs = Array({T, U}).new(size)
    zip(other) { |x, y| pairs << {x, y} }
    pairs
  end

  def zip?(other : Array)
    each_with_index do |elem, i|
      yield elem, other[i]?
    end
  end

  def zip?(other : Array(U))
    pairs = Array({T, U?}).new(size)
    zip?(other) { |x, y| pairs << {x, y} }
    pairs
  end

  private def check_needs_resize
    double_capacity if @size == @capacity
  end

  private def double_capacity
    resize_to_capacity(@capacity == 0 ? 3 : (@capacity * 2))
  end

  private def resize_to_capacity(capacity)
    @capacity = capacity
    if @buffer
      @buffer = @buffer.realloc(@capacity)
    else
      @buffer = Pointer(T).malloc(@capacity)
    end
  end

  protected def self.quicksort!(a, n, comp)
    return if (n < 2)
    p = a[n / 2]
    l = a
    r = a + n - 1
    while l <= r
      if comp.call(l.value, p) < 0
        l += 1
      elsif comp.call(r.value, p) > 0
        r -= 1
      else
        t = l.value
        l.value = r.value
        l += 1
        r.value = t
        r -= 1
      end
    end
    quicksort!(a, (r - a) + 1, comp) unless r == a + n - 1
    quicksort!(l, (a + n) - l, comp) unless l == a
  end

  protected def self.quicksort!(a, n)
    return if (n < 2)
    p = a[n / 2]
    l = a
    r = a + n - 1
    while l <= r
      if l.value < p
        l += 1
      elsif r.value > p
        r -= 1
      else
        t = l.value
        l.value = r.value
        l += 1
        r.value = t
        r -= 1
      end
    end
    quicksort!(a, (r - a) + 1) unless r == a + n - 1
    quicksort!(l, (a + n) - l) unless l == a
  end

  private def check_index_out_of_bounds(index)
    index += size if index < 0
    unless 0 <= index < size
      raise IndexError.new
    end
    index
  end

  protected def to_lookup_hash
    to_lookup_hash { |elem| elem }
  end

  protected def to_lookup_hash(&block : T -> U)
    each_with_object(Hash(U, T).new) do |o, h|
      key = yield o
      unless h.has_key?(key)
        h[key] = o
      end
    end
  end

  private def range_to_index_and_count(range)
    from = range.begin
    from += size if from < 0
    raise IndexError.new if from < 0

    to = range.end
    to += size if to < 0
    to -= 1 if range.excludes_end?
    size = to - from + 1
    size = 0 if size < 0

    {from, size}
  end

  # :nodoc:
  class ItemIterator(T)
    include Iterator(T)

    def initialize(@array : Array(T), @index = 0)
    end

    def next
      value = @array.at(@index) { stop }
      @index += 1
      value
    end

    def rewind
      @index = 0
      self
    end
  end

  # :nodoc:
  class IndexIterator(T)
    include Iterator(Int32)

    def initialize(@array : Array(T), @index = 0)
    end

    def next
      return stop if @index >= @array.size

      value = @index
      @index += 1
      value
    end

    def rewind
      @index = 0
      self
    end
  end

  # :nodoc:
  class ReverseIterator(T)
    include Iterator(T)

    def initialize(@array : Array(T), @index = array.size - 1)
    end

    def next
      return stop if @index < 0

      value = @array.at(@index) { stop }
      @index -= 1
      value
    end

    def rewind
      @index = @array.size - 1
      self
    end
  end

  # :nodoc:
  class PermutationIterator(T)
    include Iterator(Array(T))

    def initialize(@array : Array(T), @size)
      @n = @array.size
      @cycles = (@n - @size + 1..@n).to_a.reverse!
      @pool = @array.dup
      @stop = @size > @n
      @i = @size - 1
      @first = true
    end

    def next
      return stop if @stop

      if @first
        @first = false
        return @pool[0, @size]
      end

      while @i >= 0
        ci = (@cycles[@i] -= 1)
        if ci == 0
          e = @pool[@i]
          (@i + 1).upto(@n - 1) { |j| @pool[j - 1] = @pool[j] }
          @pool[@n - 1] = e
          @cycles[@i] = @n - @i
        else
          @pool.swap @i, -ci
          value = @pool[0, @size]
          @i = @size - 1
          return value
        end
        @i -= 1
      end

      @stop = true
      stop
    end

    def rewind
      @cycles = (@n - @size + 1..@n).to_a.reverse!
      @pool.replace(@array)
      @stop = @size > @n
      @i = @size - 1
      @first = true
      self
    end
  end

  # :nodoc:
  class CombinationIterator(T)
    include Iterator(Array(T))

    def initialize(array : Array(T), @size)
      @n = array.size
      @copy = array.dup
      @pool = array.dup
      @indices = (0...@size).to_a
      @stop = @size > @n
      @i = @size - 1
      @first = true
    end

    def next
      return stop if @stop

      if @first
        @first = false
        return @pool[0, @size]
      end

      while @i >= 0
        if @indices[@i] != @i + @n - @size
          @indices[@i] += 1
          @pool[@i] = @copy[@indices[@i]]

          (@i + 1).upto(@size - 1) do |j|
            @indices[j] = @indices[j - 1] + 1
            @pool[j] = @copy[@indices[j]]
          end

          value = @pool[0, @size]
          @i = @size - 1
          return value
        end
        @i -= 1
      end

      @stop = true
      stop
    end

    def rewind
      @pool.replace(@copy)
      @indices = (0...@size).to_a
      @stop = @size > @n
      @i = @size - 1
      @first = true
      self
    end
  end

  # :nodoc:
  class RepeatedCombinationIterator(T)
    include Iterator(Array(T))

    def initialize(array : Array(T), @size)
      @n = array.size
      @copy = array.dup
      @indices = Array.new(@size, 0)
      @pool = @indices.map { |i| @copy[i] }
      @stop = @size > @n
      @i = @size - 1
      @first = true
    end

    def next
      return stop if @stop

      if @first
        @first = false
        return @pool[0, @size]
      end

      while @i >= 0
        if @indices[@i] != @n - 1
          ii = @indices[@i] + 1
          tmp = @copy[ii]
          @indices.fill(@i, @size - @i) { ii }
          @pool.fill(@i, @size - @i) { tmp }

          value = @pool[0, @size]
          @i = @size - 1
          return value
        end
        @i -= 1
      end

      @stop = true
      stop
    end

    def rewind
      if @n > 0
        @indices.fill(0)
        @pool.fill(@copy[0])
      end
      @stop = @size > @n
      @i = @size - 1
      @first = true
      self
    end
  end

  # :nodoc:
  struct FlattenHelper(T)
    def self.flatten(ary)
      result = [] of T
      flatten ary, result
      result
    end

    def self.flatten(ary : Array, result)
      ary.each do |elem|
        flatten elem, result
      end
    end

    def self.flatten(other : T, result)
      result << other
    end

    def self.element_type(ary)
      if ary.is_a?(Array)
        element_type(ary.first)
      else
        ary
      end
    end
  end
end
