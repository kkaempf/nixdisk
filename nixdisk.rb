#!/usr/bin/env ruby
#
# nixtape.rb
#
# An implementation of the ECMA-57 [1] (1976) standard
# Other relevant standards: ECMA-13 [2] (Nov 67) and IBM's "DFSMS Using Magnetic Tapes" [3] (1972)
#
# Motivation: Documentation and archiving of Nixdorf 8820 hard-sectored 8" floppy disks
#
# Copyright (c) Klaus Kämpf 2021
#
# License: MIT
#
# [1] https://www.ecma-international.org/wp-content/uploads/ECMA-58_2nd_edition_january_1981.pdf
# [2] https://www.ecma-international.org/wp-content/uploads/ECMA-13_4th_edition_december_1985.pdf
# [3] http://publibz.boulder.ibm.com/epubs/pdf/dgt3m300.pdf
#
VERSION = "0.0.1"
SECSIZE = 128
       #     0   1   2   3   4   5   6   7   8   9   A   B   C   D   E   F
EBCDIC = "\x00\xb7\xb7\xb7\xb7\x08\xb7\x7f\xb7\xb7\xb7\xb7\xb7\x0d\xb7\xb7" + # 0x00
         "\xb7\xb7\xb7\xb7\xb7\x0a\x08\xb7\xb7\xb7\xb7\xb7\xb7\xb7\xb7\xb7" + # 0x10
         "\xb7\xb7\xb7\xb7\xb7\x0a\xb7\x1b\xb7\xb7\xb7\xb7\xb7\xb7\xb7\x07" + # 0x20
         "\xb7\xb7\xb7\xb7\xb7\xb7\xb7\xb7\xb7\xb7\xb7\xb7\xb7\xb7\xb7\xb7" + # 0x30
        #0123456789abcdef
        " ·········¢.<(+|" + # 0x40
        "&·········!$*);¬" + # 0x50
        "-/········|,%_>?" + # 0x60
        "·········`:#@'=\"" + # 0x70
        "·abcdefghi·····\xb1" + # 0x80
        "·jklmnopqr······" + # 0x90
        "·~stuvwxyz······" + # 0xa0
        "^·········[]····" + # 0xb0
        "{ABCDEFGHI······" + # 0xc0
        "}JKLMNOPQR······" + # 0xd0
        "\\ÜSTUVWXYZ······" + # 0xe0
        "0123456789······" # 0xf0

def usage message=nil
  STDERR.puts message if message
  STDERR.puts "Usage:"
  STDERR.puts "ibmtape <image>"
  exit 1
end

class Disk
  SECPERTRACK = 26

  #
  # seek disk position
  #
  # pos = Array of [track, side, sector]
  # track (cylinder) counts from 0
  # side is 0 for front and 1 for back
  # sector counts from 1 (see ECMA 58)
  #
  def seek pos
#    puts "seek #{pos.inspect}"
    case pos
    when Array
      track, side, sector = pos
#    puts "Seek T#{track},S#{sector}"
      @disk.seek ((track*(side+1))*SECPERTRACK+sector-1)*SECSIZE, IO::SEEK_SET
    when Integer
      @disk.seek pos, IO::SEEK_SET
    else
      raise "Unknown seek value #{pos.inspect}"
    end
  end

  #
  # get record at current position
  #
  def get size=SECSIZE
    @record = @disk.read size
  end
  
  #
  # get SECSIZE bytes at position
  #
  def get_at pos
    seek pos
    get
  end

  def conv s
    begin
#      STDERR.puts "conv(#{s.inspect})"
      a = s.split('').map{ |c| EBCDIC[c.ord,1] }.join('')
#      STDERR.puts " = >#{a}<"
    end
    a
  end

  #
  # extract label from record
  #
  # returns [ <label identifier>, <label number> ]
  #
  def label record
    record.unpack("a3a1").map { |s| conv s }
  end

  #
  # find label
  #
  # returns label number
  # nil if label not found
  #
  def find what, start = nil
    seek start if start
    l,n = label get
    return n if l == what
    nil
  end

  # unpack <length> bytes from current record as string
  # start = start byte, counting from 1 ! (because ECMA does)
  # convert EBCDIC->ASCII
  # return String
  def unpack_s start, length
    s = @record[start-1,length].unpack1("a*")
    begin
      conv(s).strip
    rescue Exception => e
      STDERR.puts "Failed EBCDIC #{s.inspect}"
      raise e
    end
  end

  # unpack <length> bytes from current record as sequence of digits
  # start = start byte, counting from 1 ! (because ECMA does)
  # convert EBCDIC->ASCII
  # return Integer
  def unpack_i start, length
    s = @record[start-1,length].unpack1("a*")
#    STDERR.puts "unpack_i(#{start}:#{length}) = #{s.inspect}"
    begin
      conv(s).to_i
    rescue Exception => e
      STDERR.puts "Failed EBCDIC #{s.inspect}"
      raise e
    end
  end

  #
  # unpack date, 6 bytes (YYMMDD) from start
  #
  # return NixDate
  #
  def unpack_date start
    NixDate.new(unpack_s start,6)
  end

  attr_reader :record

  def initialize imagename
    @filename = imagename
    unless File.readable?(imagename)
      usage "Can't read '#{imagename}'"
    end
    @disk = File.open(imagename, "r")
  end
end

class Volume
  attr_reader :number, :ident, :rlen, :seq, :disk 
  def initialize disk
    @disk = disk
    #
    # Section 5.6 - Index cylinder, VOL1 at Cyl 0, Side 0, Sector 7
    #
    @number = @disk.find "VOL", [0, 0, 7]
    raise "VOL1 not found" unless @number == "1"
    # @disk is now positioned at VOL1
    # See Section 7.3 for unpack pattern
    @ident = @disk.unpack_s 5,6
    @access = @disk.unpack_s 11,1
    @owner = @disk.unpack_s 38,14
    @seq = @disk.unpack_i 77,2
    @version = @disk.unpack_s 80, 1
    @surface = case @disk.unpack_s(72,1)
               when '', '1' then "Side 0 formatted according to ECMA-54"
               when '2' then "Both sides formatted according to ECMA-59"
               when 'M' then "Both sides formatted according to ECMA-69"
               else
                 @disk.unpack_s(72,1).inspect
               end
    @rlen = case @disk.unpack_s(76,1)
            when '' then 128
            when '1' then 256
            when '2' then 512
            when '3' then 1024
            else
              @disk.unpack_s(76,1).inspect
            end
    @alloc = case @disk.unpack_s(79,1)
             when '' then "Single sided"
             when '1' then "Double sided"
             else
               @disk.unpack_s(79,1).inspect
             end
  end
  def to_s
    "\
    Volume Identifier                 #{@ident.inspect}
    Volume Accessibility Indicator    #{(@access==' ')?'- unrestricted -':@access.inspect}
    Owner                             #{@owner.inspect}
    Surface Indicator                 #{@surface}
    Physical Record Length Identifier #{@rlen} bytes per physical record
    Sector Sequence Indicator         #{@seq.inspect}
    File Label Allocation             #{@alloc}
    Label Standard Version            #{@version.inspect}
"
  end
end

class NixDate
  def initialize s
    @year, @month, @day = s.unpack("a2 a2 a2").map &:to_i
#    STDERR.puts "NixDate(#{s}) = #{self}"
  end
  def to_s
    return "" if @day == 0
    m = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"][@month-1]
    "#{@day}. #{m} 19#{@year}"
  end
end

class Extend
  def initialize s
    @cylinder, @side, @sector = s.unpack("a2 a1 a2").map &:to_i
  end
  def to_s
    "Cyl #{@cylinder}, Side #{@side}, Sector #{@sector}"
  end
end

#
# VolumeHeader - named "File Label" in ECMA 58 7.4
#
# Nixdorf uses this to describe the disk as a whole
# Individual files have a FileHeader (also 'HDR1' prefixed :-/)
#
class VolumeHeader
  # initialize VolumeHeader (HDR1) from disk at sector
  def initialize disk, pos
    @number = disk.find "HDR", pos
    raise "HDR1 not found" unless @number == "1"

    #
    # Section 7.4 - File label HDR1
    #
    @identifier = disk.unpack_s 6,9
    @blocklen = disk.unpack_i 23,5
    @ext_beg = Extend.new(disk.unpack_s 29,5)
    @ext_end = Extend.new(disk.unpack_s 35,5)
    @rformat = disk.unpack_s 40,1
    @bypass = disk.unpack_s 41,1
    @access = disk.unpack_s 42,1
    @wp = disk.unpack_s 43,1
    @interchange = disk.unpack_s 44,1
    @multi = disk.unpack_s 45,1
    @section = disk.unpack_s 46,2
    @cdate = disk.unpack_date 48
    @rlen = disk.unpack_i 54,4
    @next_record = disk.unpack_i 58,5
    @attrib = disk.unpack_s 63,1
    @organization = disk.unpack_s 64,1
    @expiration = disk.unpack_date 67
    @verify = disk.unpack_s 73,1
    @eod = Extend.new(disk.unpack_s 75,5)

  end
  def to_s
    "\
Header
    File Identifier             #{@identifier}
    Block Length                #{@blocklen}
    Begin of Extend             #{@ext_beg}
    End of Extend               #{@ext_end}
    Record Format               #{@rformat}
    Bypass Indicator            #{@bypass}
    File Accessibility          #{@access}
    Write Protect               #{@wp}
    Interchange Type            #{@interchange}
    Multivolume Indicator       #{@multi}
    File Section Number         #{@section}
    Creation Date               #{@cdate}
    Record Length               #{@rlen}
    Offset to Next Record Space #{@next_record}
    Record Attribute            #{@attrib}
    File Organization           #{@organization}
    Expiration Date             #{@expiration}
    Verify/Copy Indicator       #{@verify}
    End of Data                 #{@eod}
"
  end
end

class ErrorMap
  def initialize disk
    @disk = disk
    #
    # Section 5.6 - Index cylinder, VOL1 at Cyl 0, Side 0, Sector 5
    #
    @a = @disk.find "ERM", [0, 0, 5]
    raise "ERMAP not found" unless @a == "A"
    #
    # Section 7.5 - ERMAP label
    #
    @defect1 = @disk.unpack_s 7,3
    @defect2 = @disk.unpack_s 11,3
    @reloc = @disk.unpack_s 23,1
    @error_dir_indicator = @disk.unpack_s 24,1
    @error_directory_c = @disk.unpack_s 25,48
  end
  def to_s
    "Error map
    Defective Cylinder 1 #{@defect1}
    Defective Cylinder 2 #{@defect2}
    Alternative Relocation Indicator #{@reloc}
    Error Directory Indicator #{@error_dir_indicator}
    Error Directory C #{@error_directory_c}
"
  end
end

#---------------------------------------------------------------------

#
# Individual files have a FileHeader
# (VolumeHeader is also 'HDR1' prefixed :-/)
#
class FileHeader
  attr_reader :name, :start, :end, :length, :rsize
  def initialize directory, pos
    @directory = directory
    disk = directory.volume.disk
    #
    # HDR1
    #
    disk.seek pos
    data = disk.get 80
    unless disk.conv(data[0,4]) == "HDR1"
      raise "FileHeader HDR1 not found at 0x#{pos.to_s(16)}"
    end

    @name = disk.unpack_s 5,23
    @remainder1 = disk.unpack_s 28, 100

    #
    # HDR2
    #
    data = disk.get 48
    unless disk.conv(data[0,4]) == "HDR2"
      raise "HDR2 not found"
    end
    @u = disk.unpack_s 5, 1
    @rsize = disk.unpack_i 6, 5
    @start = data[15,2].unpack1("S>1")
    @next_header = data[19,2].unpack1("S>1")
    @end = data[23,2].unpack1("S>1")
    @last = data[25,2].unpack1("S>1")

    @length = (@end - @start)*SECSIZE + @last
#    @length = SECSIZE if @length == 0 # ?!
    #
    # "  00"
    #
    data = disk.get 128
    unless disk.conv(data[0,4]) == "  00"
      raise "'  00' not found"
    end
    @date1 = disk.unpack_date 117
    @date2 = disk.unpack_date 123
  end
  def to_s
    "\
FileHeader1
    Name  #{@name}
    ?     #{@remainder1.inspect}
FileHeader2
    u     #{@u}
    rsize #{@rsize}
    start #{@start} (0x#{((@start - @directory.magic) * SECSIZE).to_s(16)})
    next header #{@next_header}
    end   #{@end} (0x#{((@end - @directory.magic) * SECSIZE).to_s(16)})
    bytes in last record: #{@last}
    
    computed length #{@length}
FileHeader00
    Date1 #{@date1}
    Date2 #{@date2}
"
  end
end

class NixFile
  def initialize directory, start
    @directory = directory
    @disk = directory.volume.disk
    @offset = (start - directory.magic) * SECSIZE;
    @fh = FileHeader.new directory, @offset
  end
  def to_s
    @fh.to_s
  end
  def copy name=nil
    name ||= @fh.name
    pos = @fh.start
    len = @fh.length
    File.open(name, "w+") do |f|
      while pos <= @fh.end do
        off = (pos - @directory.magic) * SECSIZE;
        data = @disk.get_at off
        if len < SECSIZE
          f.write data[0,len]
        else
          f.write data
        end
        pos += 1
        len -= SECSIZE
      end
    end
  end
end

#---------------------------------------------------------------------
# Directory


#
# One entry in the main directory
#

class DirEntry
  attr_reader :name, :flag, :start
  def initialize directory, data
#    puts "DirEntry #{data.inspect}"
    @name = directory.volume.disk.conv(data[0,8])
#    puts "=> #{@name}"
    @flag = data[8,1].unpack1("C1")
    @start = data[9,2].unpack1("S>1")
    @offset = (@start - directory.magic) * SECSIZE;
  end
  def to_s
    "#{@name} #{(@flag == 0x40)?"<SYS>":"     "} #{@start} (0x#{@offset.to_s(16)})"
  end
end

#
# Main directory (usually at [1, 0, 5] aka 0xf00)
#

class NixDir
  attr_reader :volume, :magic
  def initialize volume
    @volume = volume
    case volume.rlen
    when 128
      @volume.disk.seek [1, 0, (@volume.seq==13)?1:@volume.seq]
      @magic = 76
    when 256
      @volume.disk.seek [1, 0, @volume.seq]
      @magic = 71
    else
      STDERR.puts "Don't know where to find directory for Volume.rlen #{volume.rlen}"
    end
    offset = 0
    @entries = []
    loop do
      data = @volume.disk.get 11
      break if data.unpack1("c1") == -1
      begin
        @entries << DirEntry.new(self, data)
#      rescue
#        STDERR.puts "Bad directory (after #{@entries.length} entries)"
#        break
      end
    end
  end
  def to_s
    "Directory\n" + (@entries.map{|d| "  #{d}"}).join("\n")
  end
  def find name
    @entries.each do |e|
      return e if e.name == name
    end
    nil
  end
end


#---------------------------------------------------------------------

#
# Complete Nixdorf 8820 disk
#

class NixDisk
  attr_reader :disk, :volume, :headers, :errormap, :directory
  def initialize imagename
    @disk = Disk.new imagename
    @errormap = ErrorMap.new @disk
    @volume = Volume.new @disk
    @headers = []
    #
    # Section 5.6 - Index cylinder, VOL1 at Cyl 0, Side 0, Sector 8-26
    #
    (8..26).each do |sector|
      begin
        @headers << VolumeHeader.new(@disk, [0, 0, sector])
      rescue
        break
      end
    end
    @directory = NixDir.new @volume
  end
end

#---------------------------------------------------------------------
# main

imagename = ARGV.shift
filename = ARGV.shift
usage "image missing" if imagename.nil?

nixdisk = NixDisk.new imagename
unless filename
  puts nixdisk.volume
  puts "#{nixdisk.headers.length} Headers"
  nixdisk.headers.each do |h|
  #  puts h
  end
end
# puts nixdisk.errormap
if filename
  entry = nixdisk.directory.find filename
  if entry.nil?
    STDERR.puts "File '#{filename}' not found"
    exit 1
  end
  if entry.flag != 0x40
    file = NixFile.new nixdisk.directory, entry.start
    puts file
    file.copy filename
  else
    STDERR.puts "Can't handle #{entry}"
  end
else
  puts nixdisk.directory
end
puts "Ok"

