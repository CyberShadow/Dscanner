//          Copyright Brian Schott (Hackerpilot) 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module analysis.format_string;

import std.d.ast;
import std.d.lexer;
import analysis.base;
import std.container;
import std.regex : Regex, regex, matchAll;

/**
 * Checks format strings.
 */
class FormatStringCheck : BaseAnalyzer
{
	alias visit = BaseAnalyzer.visit;

	enum string KEY = "dscanner.suspicious.format_string";

	/**
	 * Params:
	 *     fileName = the name of the file being analyzed
	 */
	this(string fileName)
	{
		super(fileName);
		foreach (name; ["format", "writef", "writefln"])
			formatFuncs[name] = true;
	}

	bool[string] formatFuncs;

	override void visit(const FunctionCallExpression fce)
	{
		scope(success) super.visit(fce);

		auto ue = fce.unaryExpression;
		if (!ue) return;
		auto pe = ue.primaryExpression;
		if (!pe) return;
		auto ie = pe.identifierOrTemplateInstance;
		if (!ie) return;
		if (ie.identifier.text !in formatFuncs) return;
		if (!fce.arguments || !fce.arguments.argumentList) return;
		auto args = fce.arguments.argumentList.items;
		if (!args.length) return;

		//addErrorMessage(0, 0, KEY,
		//	ie.identifier.text);

	//	import std.stdio : stderr;
	//	foreach (i, foo; p.tupleof)
	//		static if (is(typeof(!!foo)))
	//			stderr.writeln(__traits(identifier, p.tupleof[i]), " - ", !!foo);
	//	stderr.writeln("------------------------------------");
	//	stderr.writeln(ie.identifier.text == tok!"writef");
	//	stderr.writeln(args.length);

		auto aue = cast(UnaryExpression)args[0];
		if (!aue) return;
		auto ape = aue.primaryExpression;
		if (!ape) return;
		if (ape.primary != tok!"stringLiteral"
		 && ape.primary != tok!"wstringLiteral"
		 && ape.primary != tok!"dstringLiteral")
			return;
		auto str = ape.primary.text;

		size_t n;
		bool wasPercent = false;
		foreach (c; str)
		{
			if (c == '%')
				if (wasPercent)
				{
					n--;
					wasPercent = false;
				}
				else
				{
					n++;
					wasPercent = true;
				}
			else
				wasPercent = false;
		}

		if (args.length - 1 != n)
			addErrorMessage(0, 0, KEY,
				"Mismatched number of format-string arguments: " ~ str);
	}
}

/*
unittest
{
	import analysis.config : StaticAnalysisConfig;
	import analysis.helpers : assertAnalyzerWarnings;
	import std.stdio : stderr;

	StaticAnalysisConfig sac;
	sac.format_string_check = true;
	assertAnalyzerWarnings(q{
		import std.stdio;

		void main() 
		{
		    try {
		          writefln("Too few!", 5); // bug 1
		          writefln("Too much: %d!"); // bug 2
		          writefln("Wrong format: %c!", 5); // bug 3
		                  writefln("Wrong format: %s!", 5); // bug 4
		          writefln("Wrong format: %d!", "a");    // bug 5
		    }
		    catch (Exception e) { // here just bugs 2 and 3 and 5 are catched!
		        writeln(e);
		    }
		}
	}c, sac);

	stderr.writeln("Unittest for FormatStringCheck passed.");
}
*/
