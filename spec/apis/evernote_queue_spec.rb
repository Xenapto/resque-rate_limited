require 'spec_helper'
require 'resque/rate_limited'

class RateLimitDuration
  def self.seconds
    60
  end
end

class RateLimitedTestQueueEn
  def self.perform(succeed)
    return if succeed

    raise(
      Evernote::EDAM::Error::EDAMSystemException,
      errorCode: Evernote::EDAM::Error::EDAMErrorCode::RATE_LIMIT_REACHED,
      rateLimitDuration: RateLimitDuration
    )
  end
end

class RateLimitedTestQueueOther
  def self.perform
    raise(Evernote::EDAM::Error::EDAMSystemException)
  end
end

describe Resque::Plugins::RateLimited::EvernoteQueue do
  before do
    allow(Resque::Plugins::RateLimited::EvernoteQueue).to receive(:paused?).and_return(false)
  end
  describe 'enqueue' do
    it 'enqueues to the correct queue with the correct parameters' do
      expect(Resque).to receive(:enqueue_to).with(
        :evernote_api,
        Resque::Plugins::RateLimited::EvernoteQueue,
        RateLimitedTestQueueEn.to_s,
        true
      )
      Resque::Plugins::RateLimited::EvernoteQueue
        .enqueue(RateLimitedTestQueueEn, true)
    end
  end

  describe 'perform' do
    before do
      Resque.inline = true
    end
    context 'with everything' do
      it 'calls the class with the right parameters' do
        expect(RateLimitedTestQueueEn).to receive(:perform).with('test_param')
        Resque::Plugins::RateLimited::EvernoteQueue
          .enqueue(RateLimitedTestQueueEn, 'test_param')
      end
    end

    context 'with rate limit exception' do
      before do
        allow(Resque::Plugins::RateLimited::EvernoteQueue).to receive(:rate_limited_requeue)
      end
      it 'pauses queue when request fails' do
        expect(Resque::Plugins::RateLimited::EvernoteQueue).to receive(:pause_until)
        Resque::Plugins::RateLimited::EvernoteQueue
          .enqueue(RateLimitedTestQueueEn, false)
      end
    end

    context 'with exception that is not rate limit' do
      before do
        allow(Resque::Plugins::RateLimited::EvernoteQueue).to receive(:rate_limited_requeue)
      end
      it 'raises the exception when request fails' do
        expect do
          Resque::Plugins::RateLimited::EvernoteQueue.enqueue(RateLimitedTestQueueOther)
        end.to raise_error Evernote::EDAM::Error::EDAMSystemException
      end
    end
  end
end
