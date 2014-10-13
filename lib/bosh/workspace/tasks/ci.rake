require "git"
require "yaml"
require "membrane"
require "bosh/core/shell"

namespace :ci do
  desc "Sets bosh target specified in .ci.yml also accepts ENV['director_password']"
  task :set_target do
    bosh "-n target #{target}"
    bosh "-n login #{username} #{password}"
  end

  desc "Deploys from stable branch"
  task :deploy_stable do
    repo.checkout 'stable'
    deployments.each do |deployment|
      bosh_deployment(deployment.name)
      bosh_prepare_deployment
      bosh_deploy
    end
  end

  desc "Run deployment and tests errands as defined in .ci.yml"
  task run: [:set_target, :deploy_stable] do
    repo.checkout 'master'
    deployments.each do |deployment|
      bosh_deployment(deployment.name)

      if apply_patch_path = deployment.apply_patch
        bosh "apply deployment patch #{apply_patch_path}"
      end

      bosh_prepare_deployment
      bosh_deploy

      deployment.errands.each do |errand|
        bosh "run errand #{errand}"
      end if deployment.errands

      if create_patch_path = deployment.create_patch
        bosh "create deployment patch #{create_patch_path}"
      end
    end

    repo.branch('stable').merge('master') unless skip_merge?
  end

  def skip_merge?
    config.skip_merge || ENV['skip_merge'] =~ /^(true|t|yes|y|1)$/i
  end

  def username
    config.target.match(/^([^@:]+)/)[1] || "admin"
  end

  def password
    match = config.target.match(/^[^:@]+:([^@]+)/)
    ENV['director_password'] || match && match[1] || "admin"
  end

  def target
    config.target.split('@')[1]
  end

  def deployments
    @deployments ||= config.deployments.map { |d| OpenStruct.new(d) }
  end

  def config
    @config ||= OpenStruct.new(load_config)
  end

  def load_config
    YAML.load_file(".ci.yml").tap { |c| config_schema.validate c }
  end

  def config_schema
    Membrane::SchemaParser.parse do
      { "target"   => String,
        "deployments" => [{
          "name" => String,
          optional("apply_patch") => String,
          optional("create_patch") => String,
          optional("errands") => [String]
        }],
        optional("skip_merge") => bool
      }
    end
  end

  def repo
    @repo ||= Git.open(Dir.getwd)
  end

  def bosh_deployment(name)
    bosh "deployment #{name}"
  end

  def bosh_prepare_deployment
    bosh "prepare deployment"
  end

  def shell
    Bosh::Core::Shell.new
  end

  def bosh_deploy
    deploy_cmd = "echo 'yes' | bosh deploy"
    out = shell.run(deploy_cmd, output_command: true, last_number: 1)
    exit 1 if out =~ /error/
  end

  def bosh(command)
    shell.run "bosh #{command}", output_command: true
  end
end

