---
title: Style a Document
---
# Style a Document
Super Editor includes support for rudimentary stylesheets, which make it easy to apply sweeping
styles across all document content.

A `Stylesheet` is a priority list of `StyleRule`s. Each `StyleRule` has a `BlockSelector`, which determines for which nodes the rule applies. Think of `BlockSelector`s as rudimentary css selectors. `BlockSelector` can match all nodes, nodes of a specific type, nodes that appear after a specific node type, and so on. A `StyleRule` also includes a `Styler`, which is a function that returns the style metadata.

`SuperEditor` includes sane defaults for common node types, but you can define your own styles by providing a custom `StyleSheet`. 

## Creating a custom stylesheet

The easiest way is to create a custom stylesheet is to copy the `defaultStylesheet` and add your rules at the end. For example, to make all level one headers green, create the following stylesheet:

```dart
final myStyleSheet = defaultStylesheet.copyWith(
  addRulesAfter: [
    StyleRule(
      // Matches all level one headers.
      const BlockSelector("header1"),
      (document, node) { 
        return {
          Styles.textStyle: const TextStyle(color: Colors.green),
        };
      },  
    ),
  ],
);
```

Then pass it to `SuperEditor`.

```dart
class MyApp extends StatelessWidget { 
  @override
  Widget build(BuildContext context) {
    return SuperEditor(
      // ...
      stylesheet: myStyleSheet,
    );
  }
}
```

See the `Styles` class for the list of keys to the style metadata used by `SuperEditor`.

## Multiple matching rules

Multiple `StyleRule`s can match a single node. When that happens, `SuperEditor` attempts to merge them, by looking at each key. For example, consider the following stylesheet:

```dart
final myStyleSheet = defaultStylesheet.copyWith(
  addRulesAfter: [
    StyleRule(
      // Matches all level one headers.
      const BlockSelector("header1"),
      (document, node) { 
        return {
          Styles.textStyle: const TextStyle(color: Colors.green),
        };
      },  
    ),
    StyleRule(
      // Matches all nodes. 
      BlockSelector.all,
      (document, node) { 
        return {
          Styles.textStyle: const TextStyle(fontSize: 14),
        };
      },  
    )
  ],
);
```

Both styles will be applied. Each level one header will have green text with a font size of 14px.

If the styles can't be merged, the first one wins. For example, consider the following stylesheet:

```dart
final myStyleSheet = defaultStylesheet.copyWith(
  addRulesAfter: [
    StyleRule(
      // Matches all nodes. 
      BlockSelector.all,      
      (document, node) { 
        return {
          Styles.textAlign: TextAlign.center,
        };
      },  
    ),
    StyleRule(
      // Matches all nodes. 
      BlockSelector.all,
      (document, node) { 
        return {
          Styles.textAlign: TextAlign.right,
        };
      },  
    )
  ],
);
```

Since we cannot match two different text alignments, the first one is used. All nodes will be center-aligned. 

However, non-conflicting keys are preserved. For example, consider the following stylesheet:

```dart
final myStyleSheet = defaultStylesheet.copyWith(
  addRulesAfter: [
    StyleRule(
      // Matches all nodes. 
      BlockSelector.all,      
      (document, node) { 
        return {
          Styles.textAlign: TextAlign.center,
        };
      },  
    ),
    StyleRule(
      // Matches all nodes. 
      BlockSelector.all,
      (document, node) { 
        return {
          Styles.textAlign: TextAlign.right,
          Styles.textStyle: const TextStyle(color: Colors.green),
        };
      },  
    )
  ],
);
```

`SuperEditor` keeps the text alignment from the first rule, ignores the text alignment from the second rule, and keeps the text style from the second rule. As a result, all nodes will be center-aligned and have green text.