module RSpec
  module Matchers
    module BuiltIn
      # @api private
      # Base class for `and` and `or` compound matchers.
      class Compound < BaseMatcher
        # @private
        attr_reader :matcher_1, :matcher_2

        def initialize(matcher_1, matcher_2)
          @matcher_1 = matcher_1
          @matcher_2 = matcher_2
        end

        # @private
        def does_not_match?(_actual)
          raise NotImplementedError, "`expect(...).not_to " \
            "matcher.#{conjunction} matcher` is not supported"
        end

        # @api private
        # @return [String]
        def description
          singleline_message(matcher_1.description, matcher_2.description)
        end

        def supports_block_expectations?
          matcher_2.supports_block_expectations? &&
          matcher_1.supports_block_expectations?
        end

        def expects_call_stack_jump?
          matcher_expects_call_stack_jump?(matcher_1) ||
          matcher_expects_call_stack_jump?(matcher_2)
        end

      private

        def initialize_copy(other)
          @matcher_1 = @matcher_1.clone
          @matcher_2 = @matcher_2.clone
          super
        end

        def match(_expected, actual)
          @match_results = Hash.new do |hash, matcher|
            hash[matcher] = matcher.matches?(actual)
          end

          perform_block_matching_if_necessary
        end

        def indent_multiline_message(message)
          message.lines.map do |line|
            line =~ /\S/ ? '   ' + line : line
          end.join
        end

        def compound_failure_message
          message_1 = matcher_1.failure_message
          message_2 = matcher_2.failure_message

          if multiline?(message_1) || multiline?(message_2)
            multiline_message(message_1, message_2)
          else
            singleline_message(message_1, message_2)
          end
        end

        def multiline_message(message_1, message_2)
          [
            indent_multiline_message(message_1.sub(/\n+\z/, '')),
            "...#{conjunction}:",
            indent_multiline_message(message_2.sub(/\A\n+/, ''))
          ].join("\n\n")
        end

        def multiline?(message)
          message.lines.count > 1
        end

        def singleline_message(message_1, message_2)
          [message_1, conjunction, message_2].join(' ')
        end

        def matcher_1_matches?
          @match_results[matcher_1]
        end

        def matcher_2_matches?
          @match_results[matcher_2]
        end

        # Normally, we execute the maching sequentially. For an expression like
        # `expect(x).to foo.and bar`, this becomes:
        #
        #   expect(x).to foo
        #   expect(x).to bar
        #
        # For block expectations, we need to nest them instead, so that
        # `expect { x }.to foo.and bar` becomes:
        #
        #   expect {
        #     expect { x }.to foo
        #   }.to bar
        #
        # This is necessary so that the `expect` block is only executed once.
        #
        # This helper method takes care of that nesting.
        def perform_block_matching_if_necessary
          return unless supports_block_expectations? && Proc === actual

          inner, outer = order_block_matchers

          @match_results[outer] = outer.matches?(Proc.new do |*args|
            @match_results[inner] = inner.matches?(inner_matcher_block(args))
          end)
        end

        # Some block matchers (such as `yield_xyz`) pass args to the `expect` block.
        # When such a matcher is used as the outer matcher, we need to forward the
        # the args on to the `expect` block.
        def inner_matcher_block(outer_args)
          return actual if outer_args.empty?

          Proc.new do |*inner_args|
            unless inner_args.empty?
              raise ArgumentError, "(#{matcher_1.description}) and " \
                "(#{matcher_2.description}) cannot be combined in a compound expectation " \
                "since both matchers pass arguments to the block."
            end

            actual.call(*outer_args)
          end
        end

        # For a matcher like `raise_error` or `throw_symbol`, where the block will jump
        # up the call stack, we need to order things so that it is the inner matcher.
        # For example, we need it to be this:
        #
        #   expect {
        #     expect {
        #       x += 1
        #       raise "boom"
        #     }.to raise_error("boom")
        #   }.to change { x }.by(1)
        #
        # ...rather than:
        #
        #   expect {
        #     expect {
        #       x += 1
        #       raise "boom"
        #     }.to change { x }.by(1)
        #   }.to raise_error("boom")
        #
        # In the latter case, the after-block logic in the `change` matcher would never
        # get executed because the `raise "boom"` line would jump to the `rescue` in the
        # `raise_error` logic, so only the former case will work properly.
        #
        # This method figures out which matcher should be the inner matcher and which
        # should be the outer matcher.
        def order_block_matchers
          return matcher_1, matcher_2 unless matcher_expects_call_stack_jump?(matcher_2)
          return matcher_2, matcher_1 unless matcher_expects_call_stack_jump?(matcher_1)

          raise ArgumentError, "(#{matcher_1.description}) and " \
            "(#{matcher_2.description}) cannot be combined in a compound expectation"
        end

        def matcher_expects_call_stack_jump?(matcher)
          matcher.expects_call_stack_jump?
        rescue NoMethodError
          false
        end

        # @api public
        # Matcher used to represent a compound `and` expectation.
        class And < self
          # @api private
          # @return [String]
          def failure_message
            if matcher_1_matches?
              matcher_2.failure_message
            elsif matcher_2_matches?
              matcher_1.failure_message
            else
              compound_failure_message
            end
          end

        private

          def match(*)
            super
            matcher_1_matches? && matcher_2_matches?
          end

          def conjunction
            "and"
          end
        end

        # @api public
        # Matcher used to represent a compound `or` expectation.
        class Or < self
          # @api private
          # @return [String]
          def failure_message
            compound_failure_message
          end

        private

          def match(*)
            super
            matcher_1_matches? || matcher_2_matches?
          end

          def conjunction
            "or"
          end
        end
      end
    end
  end
end
