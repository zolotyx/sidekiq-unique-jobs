# frozen_string_literal: true

module SidekiqUniqueJobs
  #
  # Class Lock provides access to information about a lock
  #
  # @author Mikael Henriksson <mikael@zoolutions.se>
  #
  class Lock # rubocop:disable Metrics/ClassLength
    # includes "SidekiqUniqueJobs::Connection"
    # @!parse include SidekiqUniqueJobs::Connection
    include SidekiqUniqueJobs::Connection

    # includes "SidekiqUniqueJobs::Timing"
    # @!parse include SidekiqUniqueJobs::Timing
    include SidekiqUniqueJobs::Timing

    # includes "SidekiqUniqueJobs::JSON"
    # @!parse include SidekiqUniqueJobs::JSON
    include SidekiqUniqueJobs::JSON

    #
    # @!attribute [r] key
    #   @return [String] the entity redis key
    attr_reader :key

    #
    # Initialize a locked lock
    #
    # @param [String] digest a unique digest
    # @param [String] job_id a sidekiq JID
    # @param [Hash] lock_info information about the lock
    #
    # @return [Lock] a newly lock that has been locked
    #
    def self.create(digest, job_id, lock_info = {})
      lock = new(digest, time: Timing.now_f)
      lock.lock(job_id, lock_info)
      lock
    end

    #
    # Initialize a new lock
    #
    # @param [String, Key] key either a digest or an instance of a {Key}
    # @param [Timstamp, Float] time nil optional timestamp to initiate this lock with
    #
    def initialize(key, time: nil)
      @key        = get_key(key)
      @created_at = time.is_a?(Float) ? time : time.to_f
    end

    #
    # Locks a job_id
    #
    # @note intended only for testing purposez
    #
    # @param [String] job_id a sidekiq JID
    # @param [Hash] lock_info information about the lock
    #
    # @return [void]
    #
    def lock(job_id, lock_info = {})
      redis do |conn|
        conn.multi do
          conn.set(key.digest, job_id)
          conn.hset(key.locked, job_id, now_f)
          info.set(lock_info)
          conn.zadd(key.digests, now_f, key.digest)
          conn.zadd(key.changelog, now_f, changelog_json(job_id, "queue.lua", "Queued"))
          conn.zadd(key.changelog, now_f, changelog_json(job_id, "lock.lua", "Locked"))
        end
      end
    end

    #
    # Unlock a specific job_id
    #
    # @param [String] job_id a sidekiq JID
    #
    # @return [true] when job_id was removed
    # @return [false] when job_id wasn't locked
    #
    def unlock(job_id)
      locked.del(job_id)
    end

    #
    # Deletes all the redis keys for this lock
    #
    #
    # @return [Integer] the number of keys deleted in redis
    #
    def del
      redis do |conn|
        conn.multi do
          conn.zrem(DIGESTS, key.digest)
          conn.del(key.digest, key.queued, key.primed, key.locked, key.info)
        end
      end
    end

    #
    # Returns either the time the lock was initialized with or
    #   the first changelog entry's timestamp
    #
    #
    # @return [Float] a floaty timestamp represantation
    #
    def created_at
      @created_at ||= changelogs.first&.[]("time")
    end

    #
    # Returns all job_id's for this lock
    #
    # @note a JID can be present in 3 different places
    #
    #
    # @return [Array<String>] an array with JIDs
    #
    def all_jids
      (queued_jids + primed_jids + locked_jids).uniq
    end

    #
    # Returns a collection of locked job_id's
    #
    # @param [true, false] with_values false provide the timestamp for the lock
    #
    # @return [Hash<String, Float>] when given `with_values: true`
    # @return [Array<String>] when given `with_values: false`
    #
    def locked_jids(with_values: false)
      locked.entries(with_values: with_values)
    end

    #
    # Returns the queued JIDs
    #
    #
    # @return [Array<String>] an array with queued job_ids
    #
    def queued_jids
      queued.entries
    end

    #
    # Returns the primed JIDs
    #
    #
    # @return [Array<String>] an array with primed job_ids
    #
    def primed_jids
      primed.entries
    end

    #
    # Returns all matching changelog entries for this lock
    #
    #
    # @return [Array<Hash>] an array with changelogs
    #
    def changelogs
      changelog.entries(pattern: "*#{key.digest}*")
    end

    #
    # The digest key
    #
    # @note Used for exists checks to avoid enqueuing
    #   the same lock twice
    #
    #
    # @return [] <description>
    #
    def digest
      @digest ||= Redis::String.new(key.digest)
    end

    #
    # The queued list
    #
    #
    # @return [Redis::List] for queued JIDs
    #
    def queued
      @queued ||= Redis::List.new(key.queued)
    end

    #
    # The primed list
    #
    #
    # @return [Redis::List] for primed JIDs
    #
    def primed
      @primed ||= Redis::List.new(key.primed)
    end

    #
    # The locked hash
    #
    #
    # @return [Redis::Hash] for locked JIDs
    #
    def locked
      @locked ||= Redis::Hash.new(key.locked)
    end

    #
    # Information about the lock
    #
    #
    # @return [Redis::Hash] with lock information
    #
    def info
      @info ||= LockInfo.new(key.info)
    end

    #
    # A sorted set with changelog entries
    #
    # @see Changelog for more information
    #
    #
    # @return [Changelog]
    #
    def changelog
      @changelog ||= Changelog.new
    end

    #
    # A nicely formatted string with information about this lock
    #
    #
    # @return [String]
    #
    def to_s
      <<~MESSAGE
        Lock status for #{key}

                  value: #{digest.value}
                   info: #{info.value}
            queued_jids: #{queued_jids}
            primed_jids: #{primed_jids}
            locked_jids: #{locked_jids}
             changelogs: #{changelogs}
      MESSAGE
    end

    #
    # @see to_s
    #
    def inspect
      to_s
    end

    private

    #
    # Ensure the key is a {Key}
    #
    # @param [String, Key] key
    #
    # @return [Key]
    #
    def get_key(key)
      if key.is_a?(SidekiqUniqueJobs::Key)
        key
      else
        SidekiqUniqueJobs::Key.new(key)
      end
    end

    #
    # Generate a changelog entry for the given arguments
    #
    # @param [String] job_id a sidekiq JID
    # @param [String] script the name of the script generating this entry
    # @param [String] message a descriptive message for later review
    #
    # @return [String] a JSON string matching the Lua script structure
    #
    def changelog_json(job_id, script, message)
      dump_json(
        digest: key.digest,
        job_id: job_id,
        script: script,
        message: message,
        time: now_f,
      )
    end
  end
end
