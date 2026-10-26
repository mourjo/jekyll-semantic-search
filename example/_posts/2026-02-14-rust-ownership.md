---
layout: default
title: Understanding ownership in Rust
tags: [programming]
---
Every value in Rust has a single owner. When the owner goes out of scope the value is dropped, so memory is freed without a garbage collector.

References let you borrow a value without taking ownership. The borrow checker enforces at compile time that you have either one mutable reference or any number of immutable ones, which rules out data races.
