require 'spec_helper'

describe ParallelSplitTest do
  it "has a VERSION" do
    ParallelSplitTest::VERSION.should =~ /^[\.\da-z]+$/
  end

  describe ".best_number_of_processes" do
    before do
      ENV['PARALLEL_SPLIT_TEST_PROCESSES'] = nil
    end

    let(:count) { ParallelSplitTest.send(:best_number_of_processes) }

    it "uses ENV" do
      ENV['PARALLEL_SPLIT_TEST_PROCESSES'] = "5"
      count.should == 5
    end

    it "uses physical_processor_count" do
      Parallel.stub(:physical_processor_count).and_return 6
      count.should == 6
    end

    it "uses processor_count if everything else fails" do
      Parallel.stub(:physical_processor_count).and_return 0
      Parallel.stub(:processor_count).and_return 7
      count.should == 7
    end
  end

  describe "cli" do
    def run(command, options={})
      result = `#{command} 2>&1`
      message = (options[:fail] ? "SUCCESS BUT SHOULD FAIL" : "FAIL")
      raise "[#{message}] #{result} [#{command}]" if $?.success? == !!options[:fail]
      result
    end

    def write(path, content)
      run "mkdir -p #{File.dirname(path)}" unless File.exist?(File.dirname(path))
      File.open(path, 'w'){|f| f.write content }
      path
    end

    def parallel_split_test(x)
      run "PARALLEL_SPLIT_TEST_PROCESSES=2 ../../bin/parallel_split_test #{x}"
    end

    def time
      start = Time.now.to_f
      yield
      Time.now.to_f - start
    end

    let(:root) { File.expand_path('../../', __FILE__) }

    before do
      run "rm -rf spec/tmp ; mkdir spec/tmp"
      Dir.chdir "spec/tmp"
    end

    after do
      Dir.chdir root
    end

    describe "printing version" do
      it "prints version on -v" do
        parallel_split_test("-v").strip.should =~ /^[\.\da-z]+$/
      end

      it "prints version on --version" do
        parallel_split_test("--version").strip.should =~ /^[\.\da-z]+$/
      end
    end

    describe "printing help" do
      it "prints help on -h" do
        parallel_split_test("-h").should include("Usage")
      end

      it "prints help on --help" do
        parallel_split_test("-h").should include("Usage")
      end

      it "prints help on no arguments" do
        parallel_split_test("").should include("Usage")
      end
    end

    describe "running tests" do
      it "runs in different processes" do
        write "xxx_spec.rb", <<-RUBY
        describe "X" do
          it "a" do
            puts "it-ran-a-in-\#{ENV['TEST_ENV_NUMBER']}-"
          end
        end

        describe "Y" do
          it "b" do
            puts "it-ran-b-in-\#{ENV['TEST_ENV_NUMBER']}-"
          end
        end
        RUBY
        result = parallel_split_test "xxx_spec.rb"
        result.scan('1 example, 0 failures').size.should == 2
        result.scan(/it-ran-.-in-.?-/).sort.should == ["it-ran-a-in--", "it-ran-b-in-2-"]
      end

      it "runs faster" do
        write "xxx_spec.rb", <<-RUBY
        describe "X" do
          it { sleep 1  }
        end

        describe "Y" do
          it { sleep 1  }
        end
        RUBY

        time{ parallel_split_test "xxx_spec.rb" }.should < 2
      end

      it "splits based on examples" do
        write "xxx_spec.rb", <<-RUBY
        describe "X" do
          describe "Y" do
            it { sleep 1  }
            it { sleep 1  }
          end
        end
        RUBY

        result = nil
        time{ result = parallel_split_test "xxx_spec.rb" }.should < 2
        result.scan('1 example, 0 failures').size.should == 2
      end

      it "sets up TEST_ENV_NUMBER before loading the test files, so db connections are set up correctly" do
        write "xxx_spec.rb", 'puts "ENV_IS_#{ENV[\'TEST_ENV_NUMBER\']}_"'
        result = parallel_split_test "xxx_spec.rb"
        result.scan(/ENV_IS_.?_/).sort.should == ["ENV_IS_2_", "ENV_IS__"]
      end
    end
  end
end
