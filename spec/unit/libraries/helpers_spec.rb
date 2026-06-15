# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../libraries/helpers'

RSpec.describe CincOmnibus::Cookbook::Helpers do
  subject(:helper) { Class.new { include CincOmnibus::Cookbook::Helpers }.new }

  describe '#to_msys_path' do
    it 'converts a Windows drive path to MSYS POSIX form' do
      expect(helper.to_msys_path('C:\\Users\\vagrant\\cache')).to eq('/c/Users/vagrant/cache')
    end

    it 'converts a mixed-separator drive path' do
      expect(helper.to_msys_path('C:/Users/vagrant/cache')).to eq('/c/Users/vagrant/cache')
    end

    it 'lowercases the drive letter' do
      expect(helper.to_msys_path('D:\\tools')).to eq('/d/tools')
    end

    it 'leaves a path without a drive letter unchanged' do
      expect(helper.to_msys_path('/tmp/cache')).to eq('/tmp/cache')
    end
  end
end
