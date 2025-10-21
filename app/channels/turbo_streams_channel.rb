class TurboStreamsChannel < ApplicationCable::Channel
  def subscribed
    stream_from verified_stream_name
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end

  private

  def verified_stream_name
    # This matches the stream name that Turbo::StreamsChannel uses
    params[:signed_stream_name]
  end
end
