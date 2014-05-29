class MetadataPolicy
  def initialize(app, metadata)
    @app = app
    @errors = app.errors
    @metadata = metadata
  end

  def validate
    return if @metadata.nil?
    unless @metadata.kind_of?(Hash)
      @errors.add(:metadata, :invalid_metadata)
    end
  end
end
