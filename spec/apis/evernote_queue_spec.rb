require 'spec_helper'
require 'resque/rate_limited'

class RateLimitDuration
  def self.seconds
    60
  end
end

class RateLimitedTestQueueEn
  def self.perform(succeed)
    raise(
      Evernote::EDAM::Error::EDAMSystemException,
      errorCode: Evernote::EDAM::Error::EDAMErrorCode::RATE_LIMIT_REACHED,
      rateLimitDuration: RateLimitDuration
    ) unless succeed
  end
end

class RateLimitedTestQueueOther
  def self.perform
    raise(Evernote::EDAM::Error::EDAMSystemException)
  end
end

describe Resque::Plugins::RateLimited::EvernoteQueue do
  before do
    Resque::Plugins::RateLimited::EvernoteQueue.stub(:paused?).and_return(false)
  end
  describe 'enqueue' do
    it 'enqueues to the correct queue with the correct parameters' do
      Resque.should_receive(:enqueue_to).with(
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
        RateLimitedTestQueueEn.should_receive(:perform).with('test_param')
        Resque::Plugins::RateLimited::EvernoteQueue
          .enqueue(RateLimitedTestQueueEn, 'test_param')
      end
    end

    context 'with rate limit exception' do
      before do
        Resque::Plugins::RateLimited::EvernoteQueue.stub(:rate_limited_requeue)
      end
      it 'pauses queue when request fails' do
        Resque::Plugins::RateLimited::EvernoteQueue.should_receive(:pause_until)
        Resque::Plugins::RateLimited::EvernoteQueue
          .enqueue(RateLimitedTestQueueEn, false)
      end
    end

    context 'with exception that is not rate limit' do
      before do
        Resque::Plugins::RateLimited::EvernoteQueue.stub(:rate_limited_requeue)
      end
      it 'raises the exception when request fails' do
        expect do
          Resque::Plugins::RateLimited::EvernoteQueue.enqueue(RateLimitedTestQueueOther)
        end.to raise_error Evernote::EDAM::Error::EDAMSystemException
      end
    end
  end
end
