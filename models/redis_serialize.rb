module RedisSerialize 

  def self.connect_redis(host, username, port, password)
    @redis_connection = Redis.connect(:)
  end

  def save
    redis_key = 
  end

  def redis_key(key_gen)
    if self.respond_to?(key_gen)
      self.send(key_gen)
    else 
      "#{self.class_name}_#{self.id}"
    end
  end

end