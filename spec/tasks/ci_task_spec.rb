describe 'ci' do
  include_context "rake"

  let(:config) do
    { "target" => target, "deployments" => deployments, "skip_merge" => skip_merge }
  end
  let(:target) { "foo:bar@localhost:25555" }
  let(:deployments) { [{ "name" => "foo" }] }
  let(:skip_merge) { true }
  let(:repo) { instance_double("Git::Base") }
  let(:shell) { instance_double("Bosh::Workspace::Shell") }

  before do
    allow(YAML).to receive(:load_file).with(".ci.yml").and_return(config)
    allow(Git).to receive(:open).and_return(repo)
    allow(Bosh::Workspace::Shell).to receive(:new).and_return(shell)
  end

  def expect_bosh_command(cmd, options = {})
    options[:output_command] = true
    expect(shell).to receive(:run).with(cmd, options)
  end

  describe ':target' do
    def expect_bosh_login(username, password)
      expect(shell).to receive(:run).with(/#{username} #{password}/)
    end

    subject { rake["ci:target"] }

    context "with username, password, hostname and port" do
      let(:target) { "foo:bar@example.com:25555" }
      it "sets target" do
        expect_bosh_command(/target example.com:25555/)
        expect_bosh_login("foo", "bar")
        subject.invoke
      end
    end

    context "with default password" do
      let(:target) { "foo@example.com:25555" }
      it "sets target" do
        expect_bosh_command(/target example.com:25555/)
        expect_bosh_login("foo", "admin")
        subject.invoke
      end
    end

    context "environment variables" do
      let(:target) { "foo@example.com:25555" }
      it "sets target" do
        ENV['BOSH_USER'] = "env_user"
        ENV['BOSH_PASSWORD'] = "env_pw"
        expect_bosh_command(/target example.com:25555/)
        expect_bosh_login("env_user", "env_pw")
        subject.invoke
      end
    end
  end

  describe ':patch' do
    subject { rake["ci:patch"] }
    let(:already_invoked_tasks) { %w(ci:target) }

    before do
      expect_bosh_command(/deployment foo/)
    end

    it "runs" do
      subject.invoke
    end

    context "with create_patch" do
      let(:patch_path) { "foo/bar.yml" }
      let(:deployments) { [{ "name" => "foo", "create_patch" => patch_path }] }

      it "runs and creates patch" do
        expect_bosh_command(/create deployment patch #{patch_path}/)
        subject.invoke
      end
    end

    context "with apply_patch" do
      let(:patch_path) { "foo/bar.yml" }
      let(:deployments) { [{ "name" => "foo", "apply_patch" => patch_path }] }

      it "applies patch and runs" do
        expect_bosh_command(/apply deployment patch #{patch_path}/)
        subject.invoke
      end
    end
  end

  describe ':deploy' do
    subject { rake["ci:deploy"] }
    let(:already_invoked_tasks) { %w(ci:target) }
    let(:deploy_stdout) { "task 100" }

    before do
      expect_bosh_command(/deployment foo/)
      expect_bosh_command(/prepare deployment/)
      expect(shell).to receive(:run)
        .with(/bosh -n deploy/, {output_command: true, last_number: 1})
        .and_return(deploy_stdout)
    end

    it "runs" do
      subject.invoke
    end

    context "with failing deploy" do
      let(:deploy_stdout) { "Task 101 error" }
      it "fails" do
        expect { subject.invoke }.to raise_error SystemExit
      end
    end
  end

  describe ':verify' do
    subject { rake["ci:verify"] }
    let(:already_invoked_tasks) { %w(ci:target) }
    before { expect_bosh_command(/deployment foo/) }

    context "with errands" do
      let(:deployments) { [{ "name" => "foo", "errands" => ["foo", "bar"] }] }

      it "runs and executes errands" do
        expect_bosh_command(/run errand foo/)
        expect_bosh_command(/run errand bar/)
        subject.invoke
      end
    end
  end

  describe ':clean' do
    subject { rake["ci:clean"] }
    let(:already_invoked_tasks) { %w(ci:target) }

    context "DESTROY_DEPLOYMENTS set" do
      let(:deployment) { { "name" => "foo-z1" } }
      let(:deployments_stdout) do
        <<-EOF
        +------------+-------------+-------------------------------+
        | Name       | Release(s)  | Stemcell(s)                   |
        +------------+-------------+-------------------------------+
        | foo-z1     | foo/1       | stemcell-trusty-go_agent/1234 |
        +------------+-------------+-------------------------------+

        Deployments total: 1
        EOF
      end

      before do
        expect_bosh_command(/bosh -n deployments/, ignore_failures: true)
          .and_return(deployments_stdout)
        expect(YAML).to receive(:load_file).with("deployments/foo.yml")
          .and_return(deployment)
        ENV["DESTROY_DEPLOYMENTS"] = "true"
      end

      it "deletes all deployments" do
        expect_bosh_command(/delete deployment foo-z1 --force/)
        subject.invoke
      end

      context "deployment already deleted" do
        let(:deployment) { { "name" => "foo-z2" } }

        it "skips delete deployment" do
          subject.invoke
        end
      end
    end

    context "DESTROY_DEPLOYMENTS not set" do
      before { ENV.delete "DESTROY_DEPLOYMENTS" if ENV["DESTROY_DEPLOYMENTS"] }

      it "skips delete deployment" do
        expect { subject.invoke }.to raise_error /destroy_deployments/i
      end
    end
  end
end