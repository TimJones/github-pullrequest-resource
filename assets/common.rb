require 'octokit'
require 'fileutils'

Octokit.auto_paginate = true
Octokit.connection_options[:ssl] = { verify: false } if ENV['http_proxy']

class PullRequest
  def initialize(repo:, pr:)
    @repo = repo
    @pr = pr
  end

  def ready?
    statuses.empty?
  end

  def equals?(id:, sha:)
    [@pr['head']['sha'], @pr['id']] == [sha, id]
  end

  def as_json
    { ref: @pr['head']['sha'], pr: @pr['id'] }
  end

  def status!(state)
    Octokit.create_status(
      @repo.name,
      sha,
      state
    )
  end

  def id
    @pr['id']
  end

  def sha
    @pr['head']['sha']
  end

  def url
    @pr['url']
  end

  private

  def statuses
    @statuses ||= Octokit.statuses(@repo.name, sha).select do |status|
      status['context'] == 'concourseci'
    end
  end

end

class Repository
  attr_reader :name

  def initialize(name:)
    @name = name
  end

  def pull_requests
    @pull_requests ||= Octokit.pulls(name, state: 'open', sort: 'updated', direction: 'desc').map do |pr|
      PullRequest.new(repo: self, pr: pr)
    end
  end

  def next_pull_request(id: nil, sha: nil)
    return if pull_requests.empty?

    if id && sha
      current = pull_requests.find { |pr| pr.equals?(id: id, sha: sha) }
      return if current && current.ready?
    end

    pull_requests.find do |pr|
      pr != current && pr.ready?
    end
  end
end

def load_key(input)
  private_key_path = input['source']['private_key'] || ""

  if File.exist?(private_key_path)
    FileUtils.chmod(0600, private_key_path)
    system <<-SHELL
      $(ssh-agent) >/dev/null 2>&1')
      trap "kill $SSH_AGENT_PID" 0
      SSH_ASKPASS=/opt/resource/askpass.sh DISPLAY= ssh-add $private_key_path >/dev/null
    SHELL

    FileUtils.mkdir_p('~/.ssh')
    File.write('~/.ssh/config', <<-SSHCONFIG)
StrictHostKeyChecking no
LogLevel quiet
EOF
    SSHCONFIG
    FileUtils.chmod(0600, '~/.ssh/config')
  end
end