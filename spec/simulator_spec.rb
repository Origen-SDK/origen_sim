require 'spec_helper'

describe "The simulator" do

  before :all do
    # Test the build process
    #system "origen origen_sim:build"
    Origen.load_target
    Origen.enable_debugger # Show simulator output
    sim.start
  end

  after :all do
    sim.stop
  end

  def sim
    tester.simulator
  end

  it "the peek and poke methods work" do
    net = "dut.test_data"
    sim.peek(net)[0].x?.should == true
    sim.peek(net).to_i.should == nil
    sim.poke(net, 0x12)
    sim.peek(net).to_i.should == 0x12
    sim.poke(net, 0x1234)
    sim.peek(net).to_i.should == 0x1234
    sim.poke(net, 0)
    sim.peek(net).to_i.should == 0
  end

  it "the peek and poke methods work with part selects" do
    net = "dut.test_data"
    sim.poke(net, 0)
    sim.peek(net).to_i.should == 0
    sim.poke(net + "[3]", 1)
    sim.peek(net).to_i.should == 8
    sim.poke(net + "[0]", 1)
    sim.peek(net).to_i.should == 9
    sim.peek(net + "[0]").to_i.should == 1
    sim.peek(net + "[1]").to_i.should == 0
    sim.peek(net + "[2]").to_i.should == 0
    sim.peek(net + "[3]").to_i.should == 1
    sim.poke(net + "[2]", 1)
    sim.peek(net + "[2]").to_i.should == 1
    sim.peek(net + "[3:2]").to_i.should == 3
    sim.poke(net + "[7:4]", 0xF)
    sim.peek(net).to_i.should == 0x00FD
    sim.poke(net + "[3:0]", 5)
    sim.peek(net).to_i.should == 0x00F5
    sim.peek(net + "[7:4]").to_i.should == 0xF
    sim.peek(net + "[7..4]").to_i.should == 0xF
    sim.peek(net + "[3:0]").to_i.should == 0x5
    sim.peek(net + "[3..0]").to_i.should == 0x5
  end
end
