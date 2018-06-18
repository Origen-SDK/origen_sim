require 'spec_helper'

describe 'The build command' do

  it "can build a single file" do
    ARGV.pop
    ARGV << "#{Origen.root}/examples/dut.v"
    ARGV << "-s"
    ARGV << "#{Origen.root}/examples/params"

    $_testing_build_return_dut_ = true

    begin
      load "#{Origen.root}/lib/origen_sim/commands/build.rb"
    rescue SystemExit # Just to make sure the spec fails
    end

    dut.should be

    dut.pins(:soc_addr).size.should == 20
  end

  it "can pass compiler defines from the command line" do
    ARGV.pop
    ARGV << "#{Origen.root}/examples/dut.v"
    ARGV << "--define"
    ARGV << "PARAM_OVERRIDE"
    ARGV << "--define"
    ARGV << "NUMADDR=10"

    $_testing_build_return_dut_ = true

    begin
      load "#{Origen.root}/lib/origen_sim/commands/build.rb"
    rescue SystemExit # Just to make sure the spec fails
    end

    dut.should be

    dut.pins(:soc_addr).size.should == 10
  end


  it "can build multiple files" do
    ARGV.pop
    ARGV << "params.v #{Origen.root}/examples/dut.v"
    ARGV << "--define"
    ARGV << "PARAM_OVERRIDE"
    ARGV << "-s"
    ARGV << "#{Origen.root}/examples/params"

    $_testing_build_return_dut_ = true

    begin
      load "#{Origen.root}/lib/origen_sim/commands/build.rb"
    rescue SystemExit # Just to make sure the spec fails
    end

    dut.should be

    dut.pins(:soc_addr).size.should == 20
  end
end
