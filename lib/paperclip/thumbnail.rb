module Paperclip
  # Handles thumbnailing images that are uploaded.
  class Thumbnail < Processor

    attr_accessor :current_geometry, :target_geometry, :format, :whiny, :convert_options,
                  :source_file_options, :animated, :auto_orient

    # List of formats that we need to preserve animation
    ANIMATED_FORMATS = %w(gif)

    # Creates a Thumbnail object set to work on the +file+ given. It
    # will attempt to transform the image into one defined by +target_geometry+
    # which is a "WxH"-style string. +format+ will be inferred from the +file+
    # unless specified. Thumbnail creation will raise no errors unless
    # +whiny+ is true (which it is, by default. If +convert_options+ is
    # set, the options will be appended to the convert command upon image conversion
    #
    # Options include:
    #
    #   +geometry+ - the desired width and height of the thumbnail (required)
    #   +file_geometry_parser+ - an object with a method named +from_file+ that takes an image file and produces its geometry and a +transformation_to+. Defaults to Paperclip::Geometry
    #   +string_geometry_parser+ - an object with a method named +parse+ that takes a string and produces an object with +width+, +height+, and +to_s+ accessors. Defaults to Paperclip::Geometry
    #   +source_file_options+ - flags passed to the +convert+ command that influence how the source file is read
    #   +convert_options+ - flags passed to the +convert+ command that influence how the image is processed
    #   +whiny+ - whether to raise an error when processing fails. Defaults to true
    #   +format+ - the desired filename extension
    #   +animated+ - whether to merge all the layers in the image. Defaults to true
    def initialize(file, options = {}, attachment = nil)
      super

      geometry             = options[:geometry] # this is not an option
      @file                = file
      @crop                = geometry[-1,1] == '#'
      @target_geometry     = (options[:string_geometry_parser] || Geometry).parse(geometry)
      @current_geometry    = (options[:file_geometry_parser] || Geometry).from_file(@file)
      @source_file_options = options[:source_file_options]
      @convert_options     = options[:convert_options]
      @whiny               = options[:whiny].nil? ? true : options[:whiny]
      @format              = options[:format]
      @animated            = options[:animated].nil? ? true : options[:animated]
      @auto_orient         = options[:auto_orient].nil? ? true : options[:auto_orient]

      @source_file_options = @source_file_options.split(/\s+/) if @source_file_options.respond_to?(:split)
      @convert_options     = @convert_options.split(/\s+/)     if @convert_options.respond_to?(:split)

      @current_format      = File.extname(@file.path)
      @basename            = File.basename(@file.path, @current_format)
    end

    # Returns true if the +target_geometry+ is meant to crop.
    def crop?
      @crop
    end

    # Returns true if the image is meant to make use of additional convert options.
    def convert_options?
      !@convert_options.nil? && !@convert_options.empty?
    end

    # Performs the conversion of the +file+ into a thumbnail. Returns the Tempfile
    # that contains the new image.
    def make
      src = @file
      dst = Tempfile.new([@basename, @format ? ".#{@format}" : ''])
      dst.binmode

      begin
        parameters = []
        parameters << source_file_options
        parameters << "#{File.expand_path(src.path)}"
        parameters << transformation_command
        parameters << convert_options
        parameters << "#{File.expand_path(dst.path)}"

        parameters = parameters.flatten.compact.join(" ").strip.squeeze(" ")

        success = convert(parameters)
      rescue Cocaine::ExitStatusError => e
        raise Paperclip::Error, "There was an error processing the thumbnail for #{@basename}" if @whiny
      rescue Cocaine::CommandNotFoundError => e
        raise Paperclip::Errors::CommandNotFoundError.new("Could not run the `convert` command. Please install ImageMagick.")
      end

      dst
    end

    # Returns the command ImageMagick's +convert+ needs to transform the image
    # into the thumbnail.
    def transformation_command
      scale, crop = @current_geometry.transformation_to(@target_geometry, crop?)
      trans = []
      trans << "-coalesce" if animated?
      trans << "-auto-orient" if auto_orient
      trans << "-resize" << %["#{scale}"] unless scale.nil? || scale.empty?
      trans << "-crop" << %["#{crop}"] << "+repage" if crop
      trans
    end

    protected

    # Return true if the format is animated
    def animated?
      @animated && (ANIMATED_FORMATS.include?(@format.to_s) || @format.blank?)  && identified_as_animated?
    end

    # Return true if ImageMagick's +identify+ returns an animated format
    def identified_as_animated?
      ANIMATED_FORMATS.include? identify("-format %m #{@file.path}").to_s.downcase.strip
    rescue Cocaine::ExitStatusError => e
      raise Paperclip::Error, "There was an error running `identify` for #{@basename}" if @whiny
    rescue Cocaine::CommandNotFoundError => e
      raise Paperclip::Errors::CommandNotFoundError.new("Could not run the `identify` command. Please install ImageMagick.")
    end
  end
end
