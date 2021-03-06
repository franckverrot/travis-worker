require 'test_helper'

class ShellSessionTest < Test::Unit::TestCase
  include Travis::Worker

  Shell::Session.send :public, *Shell::Session.protected_instance_methods

  attr_reader :session

  def setup
    super
    Shell::Session.any_instance.stubs(:start_shell)
    Shell::Session.any_instance.stubs(:start_sandbox)
    @session = Shell::Session.new(nil, nil)
  end

  test 'echoize: echo the command before executing it (1)' do
    assert_equal "echo \\$\\ rake\nrake", session.echoize('rake')
  end

  test 'echoize: echo the command before executing it (2)' do
    assert_equal "echo \\$\\ rvm\\ use\\ 1.9.2\nrvm use 1.9.2\necho \\$\\ FOO\\=bar\\ rake\\ ci\nFOO=bar rake ci", session.echoize(['rvm use 1.9.2', 'FOO=bar rake ci'])
  end

  test 'snapshots returns the UUIDs of all snapshots in this box' do
    session.stubs(:vm_name).returns('travis-worker_1308835149')
    session.stubs(:`).returns(FIXTURES[:vboxmanage])

    expected = %w(
      fc54e7fe-7af2-496d-925a-9b29fa5d0234
      f15bc668-c09c-46c0-82b4-b621226c8bd3
      6c08e3b2-1c9c-4d9a-99eb-5abd2b2d0bdc
      1fbd6ddb-733b-4711-a1b3-05206f4396f0
      df764451-0b17-4492-974a-9f20077fc70d
      edbd462c-9fb9-40c7-aef9-8bf4978adf60
    )
    assert_equal expected, session.snapshots
  end
end

