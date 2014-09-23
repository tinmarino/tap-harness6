use TAP::Entry;
use TAP::Result;

package TAP {
	grammar Grammar {
		token TOP { ^ <line>+ $ }
		token ws { <[\s] - [\n]> }
		token line {
			^^ [ <plan> | <test> | <bailout> | <version> | <comment> | <yaml> | <sub-test> || <unknown> ] \n
		}
		token plan {
			'1..' $<count>=[\d+] [ '#' <ws>* $<directive>=[:i 'SKIP'] \S+ <ws>+ $<explanation>=[\N*] ]?
		}
		regex description {
			[ <-[\n\#\\]> | \\<[\\#]> ]+ <!after \s+>
		}
		token test {
			$<nok>=['not '?] 'ok' [ <ws> $<num>=[\d+] ]? ' -'?
				[ <ws>+ <description> ]?
				[ <ws>* '#' <ws>* $<directive>=[:i [ 'SKIP' | 'TODO'] \S* ] <ws>+ $<explanation>=[\N*] ]?
				<ws>*
		}
		token bailout {
			'Bail out!' [ <ws> $<explanation>=[\N*] ]?
		}
		token version {
			:i 'TAP version ' $<version>=[\d+]
		}
		token comment {
			'#' <ws>* $<comment>=[\N*]
		}
		regex yaml {
			$<indent>=[<ws>+] '---' \n :
			[ ^^ $<indent> $<yaml-line>=[<!after '...'> \N* \n] : ]+
			$<indent> '...'
		}
		token sub-entry {
			<plan> | <test> | <comment> || <!after <ws>+ > <unknown>
		}
		token sub-test {
			[ '    ' <sub-entry> \n ]+
			<test>
		}
		token unknown {
			\N*
		}
	}
	class Action {
		method TOP($/) {
			make [ $<line>.map(*.ast) ];
		}
		method line($/) {
			make $/.values[0].ast;
		}
		method plan($/) {
			my %args = :raw($/.Str), :tests($<count>.Int);
			if $<directive> {
				%args<skip-all explanation> = True, $<explanation>;
			}
			make TAP::Plan.new(|%args);
		}
		method !make_test($/) {
			my %args = (:raw($/.Str), :ok(!$<nok>.Str));
			%args<number> = $<num>.defined ?? $<num>.Int !! Int;
			%args<directive> = $<directive> ?? TAP::Directive::{$<directive>.Str.substr(0,4).tclc} !! TAP::No-Directive;
			%args<explanation> = ~$<explanation> if $<explanation>;
			if $<description> {
				%args<description> = $<description>.Str.subst(/\\('#'|'\\')/, $0, :g);
			}
			return %args;
		}
		method test($/) {
			make TAP::Test.new(|self!make_test($/));
		}
		method bailout($/) {
			make TAP::Bailout.new(:raw($/.Str), :explanation($<explanation> ?? ~$<explanation> !! Str));
		}
		method version($/) {
			make TAP::Version.new(:raw($/.Str), :version($<version>.Int));
		}
		method comment($/) {
			make TAP::Comment.new(:raw($/.Str), :comment($<comment>.Str));
		}
		method yaml($/) {
			my $indent = $<indent>.Str;
			my $content = $<yaml-line>.join('');
			make TAP::YAML.new(:raw($/.Str), :$content);
		}
		method sub-entry($/) {
			make $/.values[0].ast;
		}
		method sub-test($/) {
			my @entries = @<sub-entry>.map(*.ast);
			make TAP::Sub-Test.new(:@entries, |self!make_test($<test>));
		}
		method unknown($/) {
			make TAP::Unknown.new(:raw($/.Str));
		}
	}

	class Lexer {
		has Str $!buffer = '';
		our subset Output of Any:D where *.can('more');
		has Output $!output;
		has Grammar $!grammar = Grammar.new;
		has Action $!actions = Action.new;
		submethod BUILD(Supply:D :$!output) { }
		method add-data(Str $data) {
			$!buffer ~= $data;
			while ($!grammar.subparse($!buffer, :actions($!actions))) -> $match {
				$!buffer.=substr($match.to);
				for @($match.made) -> $result {
					$!output.more($result);
				}
			}
		}
		method close-data() {
			if $!buffer.chars {
				warn "Unparsed data left at end of stream: $!buffer";
			}
			$!output.done();
		}
	}
}
