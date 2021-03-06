//          Copyright Brian Schott (Hackerpilot) 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module main;

import std.algorithm;
import std.array;
import std.conv;
import std.file;
import std.getopt;
import std.path;
import std.stdio;
import std.range;
import std.lexer;
import std.d.lexer;
import std.d.parser;

import highlighter;
import stats;
import ctags;
import etags;
import astprinter;
import imports;
import outliner;
import symbol_finder;
import analysis.run;
import analysis.config;
import dscanner_version;

import inifiled;

int main(string[] args)
{
	version (unittest)
		return 0;

	bool sloc;
	bool highlight;
	bool ctags;
	bool etags;
	bool etagsAll;
	bool help;
	bool tokenCount;
	bool syntaxCheck;
	bool ast;
	bool imports;
	bool muffin;
	bool outline;
	bool tokenDump;
	bool styleCheck;
	bool defaultConfig;
	bool report;
	string symbolName;
	string configLocation;
	bool printVersion;
	bool explore;

	try
	{
		getopt(args, std.getopt.config.caseSensitive, "sloc|l", &sloc,
			"highlight", &highlight, "ctags|c", &ctags, "help|h", &help,
			"etags|e", &etags, "etagsAll", &etagsAll,
			"tokenCount|t", &tokenCount, "syntaxCheck|s", &syntaxCheck,
			"ast|xml", &ast, "imports|i", &imports, "outline|o", &outline,
			"tokenDump", &tokenDump, "styleCheck|S", &styleCheck,
			"defaultConfig", &defaultConfig, "declaration|d", &symbolName,
			"config", &configLocation, "report", &report,
			"version", &printVersion, "muffinButton", &muffin, "explore", &explore);
	}
	catch (ConvException e)
	{
		stderr.writeln(e.msg);
		return 1;
	}

	if (muffin)
	{
		stdout.writeln(
`       ___________
    __(#*O 0** @%*)__
  _(%*o#*O%*0 #O#%##@)_
 (*#@%#o*@ #o%O*%@ #o #)
 \=====================/
  |I|I|I|I|I|I|I|I|I|I|
  |I|I|I|I|I|I|I|I|I|I|
  |I|I|I|I|I|I|I|I|I|I|
  |I|I|I|I|I|I|I|I|I|I|`);
		return 0;
	}

	if (explore)
	{
		stdout.writeln("D-Scanner: Scanning...");
		stderr.writeln("D-Scanner: No new astronomical objects discovered.");
		return 1;
	}

	if (help)
	{
		printHelp(args[0]);
		return 0;
	}

	if (printVersion)
	{
		version (Windows)
			writeln(DSCANNER_VERSION);
		else
			write(DSCANNER_VERSION, " ", GIT_HASH);
		return 0;
	}

	auto optionCount = count!"a"([sloc, highlight, ctags, tokenCount,
		syntaxCheck, ast, imports, outline, tokenDump, styleCheck, defaultConfig,
		report, symbolName !is null, etags, etagsAll]);
	if (optionCount > 1)
	{
		stderr.writeln("Too many options specified");
		return 1;
	}
	else if (optionCount < 1)
	{
		printHelp(args[0]);
		return 1;
	}

	// --report implies --styleCheck
	if (report) styleCheck = true;

	StringCache cache = StringCache(StringCache.defaultBucketCount);
	if (defaultConfig)
	{
		string s = getConfigurationLocation();
		mkdirRecurse(findSplitBefore(s, "dscanner.ini")[0]);
		StaticAnalysisConfig saConfig = defaultStaticAnalysisConfig();
		writeln("Writing default config file to ", s);
		writeINIFile(saConfig, s);
	}
	else if (tokenDump || highlight)
	{
		immutable bool usingStdin = args.length == 1;
		ubyte[] bytes = usingStdin ? readStdin() : readFile(args[1]);
		LexerConfig config;
		config.stringBehavior = StringBehavior.source;
		auto tokens = byToken(bytes, config, &cache);
		if (highlight)
		{
			highlighter.highlight(tokens, args.length == 1 ? "stdin" : args[1]);
			return 0;
		}
		else if (tokenDump)
		{
			writeln("text                    blank\tindex\tline\tcolumn\ttype\tcomment");
			foreach (token; tokens)
			{
				writefln("<<%20s>>%b\t%d\t%d\t%d\t%d\t%s", token.text is null ? str(token.type) : token.text,
					token.text !is null, token.index, token.line, token.column, token.type, token.comment);
			}
			return 0;
		}
	}
	else if (symbolName !is null)
	{
		stdout.findDeclarationOf(symbolName, expandArgs(args));
	}
	else if (ctags)
	{
		stdout.printCtags(expandArgs(args));
	}
	else if (etags || etagsAll)
	{
		stdout.printEtags(etagsAll, expandArgs(args));
	}
	else if (styleCheck)
	{
		StaticAnalysisConfig config = defaultStaticAnalysisConfig();
		string s = configLocation is null ? getConfigurationLocation() : configLocation;
		if (s.exists())
			readINIFile(config, s);
		if (report)
			generateReport(expandArgs(args), config);
		else
			return analyze(expandArgs(args), config, true) ? 1 : 0;
	}
	else if (syntaxCheck)
	{
		return .syntaxCheck(expandArgs(args)) ? 1 : 0;
	}
	else
	{
		bool usingStdin = args.length == 1;
		if (sloc || tokenCount)
		{
			if (usingStdin)
			{
				LexerConfig config;
				config.stringBehavior = StringBehavior.source;
				auto tokens = byToken(readStdin(), config, &cache);
				if (tokenCount)
					printTokenCount(stdout, "stdin", tokens);
				else
					printLineCount(stdout, "stdin", tokens);
			}
			else
			{
				ulong count;
				foreach (f; expandArgs(args))
				{

					LexerConfig config;
					config.stringBehavior = StringBehavior.source;
					auto tokens = byToken(readFile(f), config, &cache);
					if (tokenCount)
						count += printTokenCount(stdout, f, tokens);
					else
						count += printLineCount(stdout, f, tokens);
				}
				writefln("total:\t%d", count);
			}
		}
		else if (imports)
		{
			const string[] fileNames = usingStdin ? ["stdin"] : args[1 .. $];
			LexerConfig config;
			config.stringBehavior = StringBehavior.source;
			auto visitor = new ImportPrinter;
			foreach (name; fileNames)
			{
				config.fileName = name;
				auto tokens = getTokensForParser(
					usingStdin ? readStdin() : readFile(name),
					config, &cache);
				auto mod = parseModule(tokens, name, null, &doNothing);
				visitor.visit(mod);
			}
			foreach (imp; visitor.imports[])
				writeln(imp);
		}
		else if (ast || outline)
		{
			string fileName = usingStdin ? "stdin" : args[1];
			LexerConfig config;
			config.fileName = fileName;
			config.stringBehavior = StringBehavior.source;
			auto tokens = getTokensForParser(
				usingStdin ? readStdin() : readFile(args[1]),
				config, &cache);
			auto mod = parseModule(tokens, fileName, null, &doNothing);

			if (ast)
			{
				auto printer = new XMLPrinter;
				printer.output = stdout;
				printer.visit(mod);
			}
			else if (outline)
			{
				auto outliner = new Outliner(stdout);
				outliner.visit(mod);
			}
		}
	}
	return 0;
}

private:

string[] expandArgs(string[] args)
{
	// isFile can throw if it's a broken symlink.
	bool isFileSafe(T)(T a)
	{
		try
		{
			return isFile(a);
		}
		catch(FileException)
		{
			return false;
		}
	}

	string[] rVal;
	if (args.length == 1)
		args ~= ".";
	foreach (arg; args[1 ..$])
	{
		if (isFileSafe(arg))
			rVal ~= arg;
		else foreach (item; dirEntries(arg, SpanMode.breadth).map!(a => a.name))
		{
			if (isFileSafe(item) && (item.endsWith(`.d`) || item.endsWith(`.di`)))
				rVal ~= item;
			else
				continue;
		}
	}
	return rVal;
}

ubyte[] readStdin()
{
	auto sourceCode = appender!(ubyte[])();
	ubyte[4096] buf;
	while (true)
	{
		auto b = stdin.rawRead(buf);
		if (b.length == 0)
			break;
		sourceCode.put(b);
	}
	return sourceCode.data;
}

ubyte[] readFile(string fileName)
{
	if (!exists(fileName))
	{
		stderr.writefln("%s does not exist", fileName);
		return [];
	}
	File f = File(fileName);
	if (f.size == 0) return [];
	ubyte[] sourceCode = uninitializedArray!(ubyte[])(to!size_t(f.size));
	f.rawRead(sourceCode);
	return sourceCode;
}

void printHelp(string programName)
{
	stderr.writefln(
`
    Usage: %s options

options:
    --help | -h
        Prints this help message

    --version
        Prints the program version

    --sloc | -l [sourceFiles]
        Prints the number of logical lines of code in the given
        source files. If no files are specified, input is read from stdin.

    --tokenCount | -t [sourceFiles]
        Prints the number of tokens in the given source files. If no files are
        specified, input is read from stdin.

    --highlight [sourceFile] - Syntax-highlight the given source file. The
        resulting HTML will be written to standard output. If no files are
        specified, input is read from stdin.

    --imports | -i [sourceFile]
        Prints modules imported by the given source file. If no files are
        specified, input is read from stdin.

    --syntaxCheck | -s [sourceFile]
        Lexes and parses sourceFile, printing the line and column number of any
        syntax errors to stdout. One error or warning is printed per line.
        If no files are specified, input is read from stdin. %1$s will exit with
        a status code of zero if no errors are found, 1 otherwise.

    --styleCheck | -S [sourceFiles]
        Lexes and parses sourceFiles, printing the line and column number of any
        static analysis check failures stdout. %1$s will exit with a status code
        of zero if no warnings or errors are found, 1 otherwise.

    --ctags | -c sourceFile
        Generates ctags information from the given source code file. Note that
        ctags information requires a filename, so stdin cannot be used in place
        of a filename.

    --etags | -e sourceFile
        Generates etags information from the given source code file. Note that
        etags information requires a filename, so stdin cannot be used in place
        of a filename.

    --etagsAll sourceFile
        Same as --etags except private and package declarations are tagged too.

    --ast | --xml sourceFile
        Generates an XML representation of the source files abstract syntax
        tree. If no files are specified, input is read from stdin.

    --declaration | -d symbolName [sourceFiles sourceDirectories]
        Find the location where symbolName is declared. This should be more
        accurate than "grep". Searches the given files and directories, or the
        current working directory if none are specified.

    --report [sourceFiles sourceDirectories]
        Generate a static analysis report in JSON format. Implies --styleCheck,
        however the exit code will still be zero if errors or warnings are
        found.

    --config configFile
        Use the given configuration file instead of the default located in
        $HOME/.config/dscanner/dscanner.ini

    --defaultConfig
        Generates a default configuration file for the static analysis checks`,
        programName);
}

private void doNothing(string, size_t, size_t, string, bool) {}

private enum CONFIG_FILE_NAME = "dscanner.ini";
version(linux) version = useXDG;
version(BSD) version = useXDG;
version(FreeBSD) version = useXDG;
version(OSX) version = useXDG;

/**
 * Locates the configuration file
 */
string getConfigurationLocation()
{
	version (useXDG)
	{
		import std.process : environment;
		string configDir = environment.get("XDG_CONFIG_HOME", null);
		if (configDir is null)
		{
			configDir = environment.get("HOME", null);
			if (configDir is null)
				throw new Exception("Both $XDG_CONFIG_HOME and $HOME are unset");
			configDir = buildPath(configDir, ".config", "dscanner", CONFIG_FILE_NAME);
		}
		else
		{
			configDir = buildPath(configDir, "dscanner", CONFIG_FILE_NAME);
		}
		return configDir;
	}
	else version(Windows)
	{
		return CONFIG_FILE_NAME;
	}
}
