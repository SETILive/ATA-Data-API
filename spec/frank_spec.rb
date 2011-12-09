require File.dirname(__FILE__) + '/spec_helper'


describe 'The Frank App' do

  it "gives a list of active keys if any exist in the system" do
    get '/'
    last_response.should be_ok
    last_response.body.should include 'Telescope Status'
    last_response.body.should include 'Frank is currently observering '
  end
  
  # it "reports the correct telescope status on the home page"
    
  # end

  #Status tests 
  it "saves the correct status when we post it if the status is allowed" do
    ["active", "inactive"].each do |status|
      post "/status/#{status}"
      last_response.status.should == 201
      RedisConnection.get("current_status").should == status 
    end 
  end

  it "failes to save the status when we post an unallowed status " do
    ["bad_status", "gibberish"].each do |status|
      RedisConnection.set "current_status","active" 
      post "/status/#{status}"
      last_response.status.should == 406
      RedisConnection.get("current_status").should == "active" 
    end 
  end

  it "should return the current status of the telescope " do
    RedisConnection.set "current_status","active" 
    post "/status/"
    last_response.status.should == 200
    last_responce.body.should  == "active" 
  end

  #Target tests
  it "On posting data should update a target " do 
    post "/target/3", {:target=>{:target_name => "kepler22b", :ra=>22, :dec=> 34.3}}
    last_response.status.should == 200
    RedisConnection.get 
  end


end