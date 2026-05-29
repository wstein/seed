---
id: "20260529100000"
aliases: ["ATN contract", "Serialized ATN boundary"]
tags: ["architecture", "atn", "interoperability"]
---
Seed's boundary with the ANTLR tool is the serialized ATN integer stream, not the grammar. The runtime deserializes that stream and simulates it; it never reconstructs an ATN from a `.g4` grammar.

## What

The ANTLR tool serializes a grammar's Augmented Transition Network to a flat array of integers. That array, plus a serialization version, is a stable, language-neutral artifact emitted identically by the canonical tool and antlr-ng. Seed consumes it as-is.

## Why

This is the single move that turns "rewrite ANTLR in Elixir" into "port a runtime." It keeps the hardest code — ATN construction and adaptive-LL(*) analysis — on the tool side, where it is already correct and tested. It also makes the existing ANTLR grammar corpus a ready-made conformance oracle: any grammar the tool can serialize, Seed can attempt to run, and decisions can be diffed against the reference runtime.

## How

When building the ATN layer, implement a deserializer that reads the integer stream exactly as the reference does, and validate it with golden fixtures exported from the tool. Track the serialization version the tool emits and fail loudly on a mismatch rather than guessing.

## Links

- [[Idiomatic Facade Over Faithful Core]] - The deserializer and simulators are part of the faithful core validated against the reference.
- [[Parsers Are Pure Functions]] - The deserialized ATN feeds pure parsing functions.
