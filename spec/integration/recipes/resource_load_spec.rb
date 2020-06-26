require "support/shared/integration/integration_helper"

describe "Resource.load_current_value" do
  include IntegrationSupport

  module Namer
    extend self
    attr_accessor :current_index
    def incrementing_value
      @incrementing_value += 1
      @incrementing_value
    end
    attr_writer :incrementing_value
  end

  before(:all) { Namer.current_index = 1 }
  before { Namer.current_index += 1 }
  before { Namer.incrementing_value = 0 }

  let(:resource_name) { :"load_current_value_dsl#{Namer.current_index}" }
  let(:resource_class) do
    result = Class.new(Chef::Resource) do
      def self.to_s; resource_name.to_s; end

      def self.inspect; resource_name.inspect; end
      property :x, default: lazy { "default #{Namer.incrementing_value}" }
      def self.created_x=(value)
        @created = value
      end

      def self.created_x
        @created
      end
      action :create do
        new_resource.class.created_x = new_resource.x
      end
    end
    result.provides resource_name
    result
  end

  # Pull on resource_class to initialize it
  before { resource_class }

  context "with a resource with load_current_value" do
    before :each do
      resource_class.load_current_value do
        x "loaded #{Namer.incrementing_value} (#{self.class.properties.sort_by { |name, p| name }
          .select { |name, p| p.is_set?(self) }
          .map { |name, p| "#{name}=#{p.get(self)}" }
          .join(", ")})"
      end
    end

    context "and a resource with x set to a desired value" do
      let(:resource) do
        e = self
        r = nil
        converge do
          r = public_send(e.resource_name, "blah") do
            x "desired"
          end
        end
        r
      end

      it "current_resource is passed name but not x" do
        expect(resource.current_value.x).to eq "loaded 3 (name=blah)"
      end

      it "resource.current_value returns a different resource" do
        expect(resource.current_value.x).to eq "loaded 3 (name=blah)"
        expect(resource.x).to eq "desired"
      end

      it "resource.current_value constructs the resource anew each time" do
        expect(resource.current_value.x).to eq "loaded 3 (name=blah)"
        expect(resource.current_value.x).to eq "loaded 4 (name=blah)"
      end

      it "the provider accesses the current value of x" do
        expect(resource.class.created_x).to eq "desired"
      end

      context "and identity: :i and :d with desired_state: false" do
        before do
          resource_class.class_eval do
            property :i, identity: true
            property :d, desired_state: false
          end
        end

        before do
          resource.i "desired_i"
          resource.d "desired_d"
        end

        it "i, name and d are passed to load_current_value, but not x" do
          expect(resource.current_value.x).to eq "loaded 3 (d=desired_d, i=desired_i, name=blah)"
        end
      end

      context "and name_property: :i and :d with desired_state: false" do
        before do
          resource_class.class_eval do
            property :i, name_property: true
            property :d, desired_state: false
          end
        end

        before do
          resource.i "desired_i"
          resource.d "desired_d"
        end

        it "i, name and d are passed to load_current_value, but not x" do
          expect(resource.current_value.x).to eq "loaded 3 (d=desired_d, i=desired_i, name=blah)"
        end
      end
    end

    let(:subresource_name) do
      :"load_current_value_subresource_dsl#{Namer.current_index}"
    end
    let(:subresource_class) do
      r = Class.new(resource_class) do
        property :y, default: lazy { "default_y #{Namer.incrementing_value}" }
      end
      r.provides subresource_name
      r
    end

    # Pull on subresource_class to initialize it
    before { subresource_class }

    let(:subresource) do
      e = self
      r = nil
      converge do
        r = public_send(e.subresource_name, "blah") do
          x "desired"
        end
      end
      r
    end

    context "and a child resource class with no load_current_value" do
      it "the parent load_current_value is used" do
        expect(subresource.current_value.x).to eq "loaded 3 (name=blah)"
      end
      it "load_current_value yields a copy of the child class" do
        expect(subresource.current_value).to be_kind_of(subresource_class)
      end
    end

    context "And a child resource class with load_current_value" do
      before do
        subresource_class.load_current_value do
          y "loaded_y #{Namer.incrementing_value} (#{self.class.properties.sort_by { |name, p| name }
            .select { |name, p| p.is_set?(self) }
            .map { |name, p| "#{name}=#{p.get(self)}" }
            .join(", ")})"
        end
      end

      it "the overridden load_current_value is used" do
        current_resource = subresource.current_value
        expect(current_resource.x).to eq "default 4"
        expect(current_resource.y).to eq "loaded_y 3 (name=blah)"
      end
    end

    context "and a child resource class with load_current_value calling super()" do
      before do
        subresource_class.load_current_value do
          super()
          y "loaded_y #{Namer.incrementing_value} (#{self.class.properties.sort_by { |name, p| name }
            .select { |name, p| p.is_set?(self) }
            .map { |name, p| "#{name}=#{p.get(self)}" }
            .join(", ")})"
        end
      end

      it "the original load_current_value is called as well as the child one" do
        current_resource = subresource.current_value
        expect(current_resource.x).to eq "loaded 5 (name=blah)"
        expect(current_resource.y).to eq "loaded_y 6 (name=blah, x=loaded 5 (name=blah))"
      end
    end
  end
end

describe "simple load_current_value tests" do
  let(:resource_class) do
    Class.new(Chef::Resource) do
      attr_writer :index # this is our hacky global state
      def index; @index ||= 1; end

      property :myindex, Integer

      load_current_value do |new_resource|
        myindex new_resource.index
      end

      action :run do
        new_resource.index += 1
      end
    end
  end

  let(:node) { Chef::Node.new }
  let(:events) { Chef::EventDispatch::Dispatcher.new }
  let(:run_context) { Chef::RunContext.new(node, {}, events) }
  let(:new_resource) { resource_class.new("test", run_context) }
  let(:provider) { new_resource.provider_for_action(:run) }

  it "calling the action on the provider sets the current_resource" do
    expect(events).to receive(:resource_current_state_loaded).with(new_resource, :run, anything)
    provider.run_action(:run)
    expect(provider.current_resource.myindex).to eql(1)
  end

  it "calling the action on the provider sets the after_resource" do
    expect(events).to receive(:resource_after_state_loaded).with(new_resource, :run, anything)
    provider.run_action(:run)
    expect(provider.after_resource.myindex).to eql(2)
  end
end

describe "simple load_current_resource tests" do
  let(:provider_class) do
    Class.new(Chef::Provider) do
      provides :no_load_current_value
      def load_current_resource
        @current_resource = new_resource.dup
        @current_resource.myindex = 1
      end
      action :run do
      end
    end
  end

  let(:resource_class) do
    provider_class # vivify the provider_class
    Class.new(Chef::Resource) do
      provides :no_load_current_value
      property :myindex, Integer
    end
  end

  let(:node) { Chef::Node.new }
  let(:events) { Chef::EventDispatch::Dispatcher.new }
  let(:run_context) { Chef::RunContext.new(node, {}, events) }
  let(:new_resource) { resource_class.new("test", run_context) }
  let(:provider) { new_resource.provider_for_action(:run) }

  it "calling the action on the provider sets the current_resource" do
    expect(events).to receive(:resource_current_state_loaded).with(new_resource, :run, anything)
    provider.run_action(:run)
    expect(provider.current_resource.myindex).to eql(1)
  end

  it "calling the action on the provider sets the after_resource" do
    expect(events).to receive(:resource_after_state_loaded).with(new_resource, :run, new_resource)
    provider.run_action(:run)
    expect(provider.after_resource.myindex).to eql(nil)
  end
end

describe "simple load_current_resource and load_after_resource tests" do
  let(:provider_class) do
    Class.new(Chef::Provider) do
      provides :load_after
      def load_current_resource
        @current_resource = new_resource.dup
        @current_resource.myindex = 1
      end

      def load_after_resource
        @after_resource = new_resource.dup
        @after_resource.myindex = 2
      end
      action :run do
      end
    end
  end

  let(:resource_class) do
    provider_class # autovivify provider class
    Class.new(Chef::Resource) do
      provides :load_after
      property :myindex, Integer
    end
  end

  let(:node) { Chef::Node.new }
  let(:events) { Chef::EventDispatch::Dispatcher.new }
  let(:run_context) { Chef::RunContext.new(node, {}, events) }
  let(:new_resource) { resource_class.new("test", run_context) }
  let(:provider) { new_resource.provider_for_action(:run) }

  it "calling the action on the provider sets the current_resource" do
    expect(events).to receive(:resource_current_state_loaded).with(new_resource, :run, anything)
    provider.run_action(:run)
    expect(provider.current_resource.myindex).to eql(1)
  end

  it "calling the action on the provider sets the after_resource" do
    expect(events).to receive(:resource_after_state_loaded).with(new_resource, :run, anything)
    provider.run_action(:run)
    expect(provider.after_resource.myindex).to eql(2)
  end
end
