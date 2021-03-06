//          Copyright Brian Schott (Hackerpilot) 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)
module analysis.unmodified;

import std.container;
import std.d.ast;
import std.d.lexer;
import analysis.base;

/**
 * Checks for variables that could have been declared const or immutable
 */
class UnmodifiedFinder:BaseAnalyzer
{
	alias visit = BaseAnalyzer.visit;

	///
	this(string fileName)
	{
		super(fileName);
	}

	override void visit(const Module mod)
	{
		pushScope();
		mod.accept(this);
		popScope();
	}

	override void visit(const BlockStatement blockStatement)
	{
		pushScope();
		blockStatementDepth++;
		blockStatement.accept(this);
		blockStatementDepth--;
		popScope();
	}

	override void visit(const StructBody structBody)
	{
		pushScope();
		auto oldBlockStatementDepth = blockStatementDepth;
		blockStatementDepth = 0;
		structBody.accept(this);
		blockStatementDepth = oldBlockStatementDepth;
		popScope();
	}

	override void visit(const VariableDeclaration dec)
	{
		if (dec.autoDeclaration is null && blockStatementDepth > 0
			&& isImmutable <= 0 && !canFindImmutable(dec))
		{
			foreach (d; dec.declarators)
			{
				if (initializedFromCast(d.initializer))
					continue;
				tree[$ - 1].insert(new VariableInfo(d.name.text, d.name.line,
					d.name.column));
			}
		}
		dec.accept(this);
	}

	override void visit(const AutoDeclaration autoDeclaration)
	{
		import std.algorithm : canFind;

		if (blockStatementDepth > 0 && isImmutable <= 0
			&& (!autoDeclaration.storageClasses.canFind!(a => a.token == tok!"const"
			|| a.token == tok!"enum" || a.token == tok!"immutable")))
		{
			foreach (size_t i, id; autoDeclaration.identifiers)
			{
				if (initializedFromCast(autoDeclaration.initializers[i]))
					continue;
				tree[$ - 1].insert(new VariableInfo(id.text, id.line,
					id.column));
			}
		}
		autoDeclaration.accept(this);
	}

	override void visit(const AssignExpression assignExpression)
	{
		if (assignExpression.operator != tok!"")
		{
			interest++;
			assignExpression.ternaryExpression.accept(this);
			interest--;
			assignExpression.assignExpression.accept(this);
		}
		else
			assignExpression.accept(this);
	}

	override void visit(const Declaration dec)
	{
		if (canFindImmutableOrConst(dec))
		{
			isImmutable++;
			dec.accept(this);
			isImmutable--;
		}
		else
			dec.accept(this);
	}

	override void visit(const IdentifierChain ic)
	{
		if (ic.identifiers.length && interest > 0)
			variableMightBeModified(ic.identifiers[0].text);
		ic.accept(this);
	}

	override void visit(const IdentifierOrTemplateInstance ioti)
	{
		if (ioti.identifier != tok!"" && interest > 0)
			variableMightBeModified(ioti.identifier.text);
		ioti.accept(this);
	}

	mixin PartsMightModify!AsmPrimaryExp;
	mixin PartsMightModify!IndexExpression;
	mixin PartsMightModify!SliceExpression;
	mixin PartsMightModify!FunctionCallExpression;
	mixin PartsMightModify!IdentifierOrTemplateChain;
	mixin PartsMightModify!ReturnStatement;

	override void visit(const UnaryExpression unary)
	{
		if (unary.prefix == tok!"++" || unary.prefix == tok!"--"
			|| unary.suffix == tok!"++" || unary.suffix == tok!"--")
		{
			interest++;
			unary.accept(this);
			interest--;
		}
		else
			unary.accept(this);
	}

	override void visit(const ForeachStatement foreachStatement)
	{
		if (foreachStatement.low !is null)
		{
			interest++;
			foreachStatement.low.accept(this);
			interest--;
		}
		foreachStatement.declarationOrStatement.accept(this);
	}

	override void visit(const TraitsExpression)
	{
		// Issue #266. Ignore everything inside of __traits expressions.
	}

private:

	template PartsMightModify(T)
	{
		override void visit(const T t)
		{
			interest++;
			t.accept(this);
			interest--;
		}
	}

	void variableMightBeModified(string name)
	{
//		import std.stdio : stderr;
//		stderr.writeln("Marking ", name, " as possibly modified");
		size_t index = tree.length - 1;
		auto vi = VariableInfo(name);
		while (true)
		{
			if (tree[index].removeKey(&vi) != 0 || index == 0)
				break;
			index--;
		}
	}

	bool initializedFromCast(const Initializer initializer)
	{
		import std.typecons : scoped;

		static class CastFinder : ASTVisitor
		{
			alias visit = ASTVisitor.visit;
			override void visit(const CastExpression castExpression)
			{
				foundCast = true;
				castExpression.accept(this);
			}
			bool foundCast = false;
		}

		if (initializer is null)
			return false;
		auto finder = scoped!CastFinder();
		finder.visit(initializer);
		return finder.foundCast;
	}

	bool canFindImmutableOrConst(const Declaration dec)
	{
		import std.algorithm : canFind, map, filter;
		return !dec.attributes.map!(a => a.attribute).filter!(
			a => a == cast(IdType) tok!"immutable" || a == cast(IdType) tok!"const")
			.empty;
	}

	bool canFindImmutable(const VariableDeclaration dec)
	{
		import std.algorithm : canFind;
		foreach (storageClass; dec.storageClasses)
		{
			if (storageClass.token == tok!"enum")
				return true;
		}
		foreach (attr; dec.attributes)
		{
			if (attr.attribute.type == tok!"immutable" || attr.attribute.type == tok!"const")
				return true;
		}
		if (dec.type !is null)
		{
			if (dec.type.typeConstructors.canFind(cast(IdType) tok!"immutable"))
				return true;
		}
		return false;
	}

	static struct VariableInfo
	{
		string name;
		size_t line;
		size_t column;
	}

	void popScope()
	{
		foreach (vi; tree[$ - 1])
		{
			immutable string errorMessage = "Variable " ~ vi.name
				~ " is never modified and could have been declared const"
				~ " or immutable.";
			addErrorMessage(vi.line, vi.column, "dscanner.suspicious.unmodified",
				errorMessage);
		}
		tree = tree[0 .. $ - 1];
	}

	void pushScope()
	{
		tree ~= new RedBlackTree!(VariableInfo*, "a.name < b.name");
	}

	int blockStatementDepth;

	int interest;

	int isImmutable;

	RedBlackTree!(VariableInfo*, "a.name < b.name")[] tree;
}

