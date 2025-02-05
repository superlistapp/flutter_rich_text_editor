import 'package:attributed_text/attributed_text.dart';
import 'package:test/test.dart';

void main() {
  group("AttributedAttributed > placeholders >", () {
    group("construction >", () {
      test("reports invalid placeholder positions", () {
        // Index less than zero.
        expect(
          () => AttributedText("Hello, World!", null, {
            -1: const _FakePlaceholder("bad-index"),
          }),
          throwsA(isA<AssertionError>()),
        );

        // Index beyond length.
        expect(
          () => AttributedText("Hello, World!", null, {
            14: const _FakePlaceholder("bad-index"),
          }),
          throwsA(isA<AssertionError>()),
        );
      });
    });

    group("length >", () {
      test("only a single placeholder", () {
        expect(
          AttributedText(
            "",
            null,
            {
              0: const _FakePlaceholder("only"),
            },
          ).length,
          1,
        );
      });

      test("only multiple placeholders", () {
        expect(
          AttributedText(
            "",
            null,
            {
              0: const _FakePlaceholder("one"),
              1: const _FakePlaceholder("two"),
              2: const _FakePlaceholder("three"),
            },
          ).length,
          3,
        );
      });

      test("text with a single placeholder", () {
        expect(
          AttributedText(
            "Hello, world! ",
            null,
            {
              14: const _FakePlaceholder("trailing"),
            },
          ).length,
          15,
        );
      });

      test("text with multiple placeholders", () {
        expect(
          AttributedText(
            "Hello, world! ",
            null,
            {
              0: const _FakePlaceholder("leading"),
              6: const _FakePlaceholder("middle"),
              16: const _FakePlaceholder("trailing"),
            },
          ).length,
          17,
        );
      });
    });

    test("reports characters and placeholders at indices", () {
      final text1 = AttributedText("HelloWorld", null, {
        0: const _FakePlaceholder("one"),
        6: const _FakePlaceholder("two"),
        12: const _FakePlaceholder("three"),
      });

      expect(text1.first, const _FakePlaceholder("one"));
      expect(text1[1], "H");
      expect(text1[6], const _FakePlaceholder("two"));
      expect(text1[11], "d");
      expect(text1.last, const _FakePlaceholder("three"));

      final text2 = AttributedText("Hello World", null, {
        0: const _FakePlaceholder("one"),
      });
      expect(text2[11], "d");
      expect(text2.last, "d");
    });

    test("reports plain text value", () {
      expect(
        AttributedText("", null, {
          0: const _FakePlaceholder("only"),
        }).toPlainText(replacementCharacter: "�"),
        "�",
      );

      expect(
        AttributedText("", null, {
          0: const _FakePlaceholder("one"),
          1: const _FakePlaceholder("two"),
          2: const _FakePlaceholder("three"),
        }).toPlainText(replacementCharacter: "�"),
        "���",
      );

      expect(
        AttributedText("HelloWorld", null, {
          0: const _FakePlaceholder("one"),
          6: const _FakePlaceholder("two"),
          12: const _FakePlaceholder("three"),
        }).toPlainText(replacementCharacter: "�"),
        "�Hello�World�",
      );
    });

    group("plain text substring >", () {
      test("when placeholders are not in range", () {
        expect(
          AttributedText("Hello, world!", null, {
            0: const _FakePlaceholder("leading"),
            6: const _FakePlaceholder("middle"),
            15: const _FakePlaceholder("trailing"),
          }).substring(1, 6),
          "Hello",
        );
      });

      test("with placeholders in the range", () {
        expect(
          AttributedText("Hello, world!", null, {
            0: const _FakePlaceholder("leading"),
            6: const _FakePlaceholder("middle"),
            15: const _FakePlaceholder("trailing"),
          }).substring(0, 7),
          "Hello",
        );
      });
    });

    group("equality >", () {
      test("only a single placeholder", () {
        expect(
          AttributedText("", null, {
            0: const _FakePlaceholder("only"),
          }),
          equals(
            AttributedText("", null, {
              0: const _FakePlaceholder("only"),
            }),
          ),
        );

        expect(
          AttributedText("", null, {
            0: const _FakePlaceholder("only"),
          }),
          isNot(
            equals(
              AttributedText("", null),
            ),
          ),
        );

        expect(
          AttributedText("", null),
          isNot(
            equals(
              AttributedText("", null, {
                0: const _FakePlaceholder("only"),
              }),
            ),
          ),
        );
      });

      test("some of multiple placeholders", () {
        expect(
          AttributedText("", null, {
            0: const _FakePlaceholder("one"),
            1: const _FakePlaceholder("two"),
            2: const _FakePlaceholder("three"),
          }),
          equals(
            AttributedText("", null, {
              0: const _FakePlaceholder("one"),
              1: const _FakePlaceholder("two"),
              2: const _FakePlaceholder("three"),
            }),
          ),
        );

        expect(
          AttributedText("", null),
          isNot(
            equals(
              AttributedText("", null, {
                0: const _FakePlaceholder("one"),
                1: const _FakePlaceholder("two"),
                2: const _FakePlaceholder("three"),
              }),
            ),
          ),
        );

        expect(
          AttributedText("", null, {
            0: const _FakePlaceholder("one"),
            1: const _FakePlaceholder("two"),
            2: const _FakePlaceholder("three"),
          }),
          isNot(
            equals(
              AttributedText("", null),
            ),
          ),
        );
      });

      test("some text and a placeholder", () {
        expect(
          AttributedText("Hello, world!", null, {
            5: const _FakePlaceholder("middle"),
          }),
          equals(
            AttributedText("Hello, world!", null, {
              5: const _FakePlaceholder("middle"),
            }),
          ),
        );

        expect(
          AttributedText("Hello, world!", null),
          isNot(
            equals(
              AttributedText("Hello, world!", null, {
                5: const _FakePlaceholder("middle"),
              }),
            ),
          ),
        );

        expect(
          AttributedText("Hello, world!", null, {
            5: const _FakePlaceholder("middle"),
          }),
          isNot(
            equals(
              AttributedText("Hello, world!", null),
            ),
          ),
        );
      });
    });

    group("attribution queries >", () {
      test('finds spans that exceed plain text length', () {
        final attributedText = AttributedText(
          'Hello world',
          AttributedSpans(
            attributions: [
              const SpanMarker(attribution: ExpectedSpans.bold, offset: 0, markerType: SpanMarkerType.start),
              const SpanMarker(attribution: ExpectedSpans.bold, offset: 12, markerType: SpanMarkerType.end),
            ],
          ),
          {
            11: const _FakePlaceholder("trailing1"),
            12: const _FakePlaceholder("trailing2"),
          },
        );

        final ranges = attributedText.getAttributionSpans({ExpectedSpans.bold});

        expect(ranges.length, 1);
        expect(
          ranges,
          [
            const AttributionSpan(attribution: ExpectedSpans.bold, start: 0, end: 12),
          ],
        );
      });
    });

    group("full copy >", () {
      test("only a single placeholder", () {
        expect(
          AttributedText(
              "",
              AttributedSpans(
                attributions: const [
                  SpanMarker(attribution: _bold, offset: 0, markerType: SpanMarkerType.start),
                  SpanMarker(attribution: _bold, offset: 0, markerType: SpanMarkerType.end),
                ],
              ),
              {
                0: const _FakePlaceholder("only"),
              }).copy(),
          AttributedText(
              "",
              AttributedSpans(
                attributions: const [
                  SpanMarker(attribution: _bold, offset: 0, markerType: SpanMarkerType.start),
                  SpanMarker(attribution: _bold, offset: 0, markerType: SpanMarkerType.end),
                ],
              ),
              {
                0: const _FakePlaceholder("only"),
              }),
        );
      });

      test("some of multiple placeholders", () {
        expect(
          AttributedText(
              "",
              AttributedSpans(
                attributions: const [
                  SpanMarker(attribution: _bold, offset: 1, markerType: SpanMarkerType.start),
                  SpanMarker(attribution: _bold, offset: 2, markerType: SpanMarkerType.end),
                ],
              ),
              {
                0: const _FakePlaceholder("one"),
                1: const _FakePlaceholder("two"),
                2: const _FakePlaceholder("three"),
              }).copy(),
          AttributedText(
              "",
              AttributedSpans(
                attributions: const [
                  SpanMarker(attribution: _bold, offset: 1, markerType: SpanMarkerType.start),
                  SpanMarker(attribution: _bold, offset: 2, markerType: SpanMarkerType.end),
                ],
              ),
              {
                0: const _FakePlaceholder("one"),
                1: const _FakePlaceholder("two"),
                2: const _FakePlaceholder("three"),
              }),
        );
      });

      test("some text and a placeholder", () {
        expect(
          AttributedText(
              "Hello, world!",
              AttributedSpans(
                attributions: const [
                  SpanMarker(attribution: _bold, offset: 0, markerType: SpanMarkerType.start),
                  SpanMarker(attribution: _bold, offset: 5, markerType: SpanMarkerType.end),
                ],
              ),
              {
                5: const _FakePlaceholder("middle"),
              }).copy(),
          AttributedText(
              "Hello, world!",
              AttributedSpans(
                attributions: const [
                  SpanMarker(attribution: _bold, offset: 0, markerType: SpanMarkerType.start),
                  SpanMarker(attribution: _bold, offset: 5, markerType: SpanMarkerType.end),
                ],
              ),
              {
                5: const _FakePlaceholder("middle"),
              }),
        );
      });
    });

    group("copy span >", () {
      test("only a single placeholder", () {
        expect(
          AttributedText("", null, {
            0: const _FakePlaceholder("only"),
          }).copyText(0, 1),
          AttributedText("", null, {
            0: const _FakePlaceholder("only"),
          }),
        );
      });

      test("some of multiple placeholders", () {
        expect(
          AttributedText("", null, {
            0: const _FakePlaceholder("one"),
            1: const _FakePlaceholder("two"),
            2: const _FakePlaceholder("three"),
          }).copyText(1, 3),
          AttributedText("", null, {
            0: const _FakePlaceholder("two"),
            1: const _FakePlaceholder("three"),
          }),
        );
      });

      test("some text and a leading placeholder", () {
        expect(
          AttributedText("Hello, world!", null, {
            0: const _FakePlaceholder("leading"),
          }).copyText(0, 6),
          AttributedText("Hello", null, {
            0: const _FakePlaceholder("leading"),
          }),
        );
      });

      test("some text and a middle placeholder", () {
        expect(
          AttributedText("Hello, world!", null, {
            5: const _FakePlaceholder("middle"),
          }).copyText(0, 6),
          AttributedText("Hello", null, {
            5: const _FakePlaceholder("middle"),
          }),
        );
      });

      test("some text and a trailing placeholder", () {
        expect(
          AttributedText("Hello, world!", null, {
            13: const _FakePlaceholder("trailing"),
          }).copyText(7, 14),
          AttributedText("world!", null, {
            6: const _FakePlaceholder("trailing"),
          }),
        );
      });

      test("empty text with leading placeholder (with attributions)", () {
        // Create an empty text containing a placeholder with an attribution around it.
        final text = AttributedText(
          '',
          AttributedSpans(
            attributions: [
              const SpanMarker(
                attribution: _bold,
                offset: 0,
                markerType: SpanMarkerType.start,
              ),
              const SpanMarker(
                attribution: _bold,
                offset: 0,
                markerType: SpanMarkerType.end,
              ),
            ],
          ),
          {
            0: const _FakePlaceholder('leading'),
          },
        );

        expect(
          text.copyText(0),
          AttributedText(
            "",
            AttributedSpans(
              attributions: const [
                SpanMarker(attribution: _bold, offset: 0, markerType: SpanMarkerType.start),
                SpanMarker(attribution: _bold, offset: 0, markerType: SpanMarkerType.end),
              ],
            ),
            {
              0: const _FakePlaceholder("leading"),
            },
          ),
        );
      });
    });

    group("copy and append >", () {
      test("only a single placeholder", () {
        expect(
          AttributedText("Hello").copyAndAppend(
            AttributedText("", null, {
              0: const _FakePlaceholder("only"),
            }),
          ),
          AttributedText("Hello", null, {
            5: const _FakePlaceholder("only"),
          }),
        );
      });

      test("some of multiple placeholders", () {
        expect(
          AttributedText("Hello").copyAndAppend(
            AttributedText("", null, {
              0: const _FakePlaceholder("one"),
              1: const _FakePlaceholder("two"),
              2: const _FakePlaceholder("three"),
            }),
          ),
          AttributedText("Hello", null, {
            5: const _FakePlaceholder("one"),
            6: const _FakePlaceholder("two"),
            7: const _FakePlaceholder("three"),
          }),
        );
      });

      test("some text and a leading placeholder", () {
        expect(
          AttributedText("Hello").copyAndAppend(
            AttributedText(", world!", null, {
              0: const _FakePlaceholder("middle"),
            }),
          ),
          AttributedText("Hello, world!", null, {
            5: const _FakePlaceholder("middle"),
          }),
        );
      });

      test("some text and a middle placeholder", () {
        expect(
          AttributedText("Hello").copyAndAppend(
            AttributedText(", world!", null, {
              2: const _FakePlaceholder("middle"),
            }),
          ),
          AttributedText("Hello, world!", null, {
            7: const _FakePlaceholder("middle"),
          }),
        );
      });

      test("some text and a trailing placeholder", () {
        expect(
          AttributedText("Hello").copyAndAppend(
            AttributedText(", world!", null, {
              8: const _FakePlaceholder("trailing"),
            }),
          ),
          AttributedText("Hello, world!", null, {
            13: const _FakePlaceholder("trailing"),
          }),
        );
      });

      test("at end of text (with attributions) with leading placeholder", () {
        // Note: We include attributions in this test because in a client app the presence
        //       of attributions unearthed a bug where we were still using the plain text
        //       length, when we should have been using the text + placeholders length.
        expect(
          AttributedText(
            "Hello",
            AttributedSpans(attributions: const [
              SpanMarker(attribution: ExpectedSpans.bold, offset: 1, markerType: SpanMarkerType.start),
              SpanMarker(attribution: ExpectedSpans.bold, offset: 5, markerType: SpanMarkerType.end),
            ]),
            {
              0: const _FakePlaceholder("leading"),
            },
          ).copyAndAppend(
            AttributedText(", world!"),
          ),
          AttributedText(
            "Hello, world!",
            AttributedSpans(attributions: const [
              SpanMarker(attribution: ExpectedSpans.bold, offset: 1, markerType: SpanMarkerType.start),
              SpanMarker(attribution: ExpectedSpans.bold, offset: 5, markerType: SpanMarkerType.end),
            ]),
            {
              0: const _FakePlaceholder("leading"),
            },
          ),
        );
      });

      test("at end of text (with attributions) with trailing placeholder", () {
        // Note: We include attributions in this test because in a client app the presence
        //       of attributions unearthed a bug where we were still using the plain text
        //       length, when we should have been using the text + placeholders length.
        expect(
          AttributedText(
            "Hello",
            AttributedSpans(attributions: const [
              SpanMarker(attribution: ExpectedSpans.bold, offset: 0, markerType: SpanMarkerType.start),
              SpanMarker(attribution: ExpectedSpans.bold, offset: 4, markerType: SpanMarkerType.end),
            ]),
            {
              5: const _FakePlaceholder("trailing"),
            },
          ).copyAndAppend(
            AttributedText(", world!"),
          ),
          AttributedText(
            "Hello, world!",
            AttributedSpans(attributions: const [
              SpanMarker(attribution: ExpectedSpans.bold, offset: 0, markerType: SpanMarkerType.start),
              SpanMarker(attribution: ExpectedSpans.bold, offset: 4, markerType: SpanMarkerType.end),
            ]),
            {
              5: const _FakePlaceholder("trailing"),
            },
          ),
        );
      });
    });

    test("insert attributed text >", () {
      final empty = AttributedText("");
      final hello = empty.insert(
        textToInsert: AttributedText("Hello", null, {
          5: const _FakePlaceholder("middle"),
        }),
        startOffset: 0,
      );
      final helloWorld = hello.insert(
        textToInsert: AttributedText(", World!", null, {
          8: const _FakePlaceholder("trailing"),
        }),
        startOffset: 6,
      );

      expect(
        hello,
        AttributedText("Hello", null, {
          5: const _FakePlaceholder("middle"),
        }),
      );

      expect(
        helloWorld,
        AttributedText("Hello, World!", null, {
          5: const _FakePlaceholder("middle"),
          14: const _FakePlaceholder("trailing"),
        }),
      );
    });

    group("insert placeholders >", () {
      test("multiple placeholders", () {
        expect(
          AttributedText("Hello, World!").insertPlaceholders({
            0: const _FakePlaceholder("leading"),
            6: const _FakePlaceholder("middle"),
            14: const _FakePlaceholder("trailing"),
          }),
          AttributedText("Hello, World!", null, {
            0: const _FakePlaceholder("leading"),
            6: const _FakePlaceholder("middle"),
            14: const _FakePlaceholder("trailing"),
          }),
        );
      });

      test("individual placeholder", () {
        expect(
          AttributedText().insertPlaceholder(0, const _FakePlaceholder("only")),
          AttributedText("", null, {
            0: const _FakePlaceholder("only"),
          }),
        );

        expect(
          AttributedText("Hello").insertPlaceholder(5, const _FakePlaceholder("only")),
          AttributedText("Hello", null, {
            5: const _FakePlaceholder("only"),
          }),
        );
      });
    });

    test("remove region >", () {
      expect(
        AttributedText(
          "Hello, World!",
          AttributedSpans(
            attributions: const [
              SpanMarker(attribution: _bold, offset: 0, markerType: SpanMarkerType.start),
              SpanMarker(attribution: _bold, offset: 4, markerType: SpanMarkerType.end),
            ],
          ),
          {
            5: const _FakePlaceholder("middle"),
          },
        ).removeRegion(startOffset: 0, endOffset: 5),
        AttributedText(
          ", World!",
          null,
          {
            0: const _FakePlaceholder("middle"),
          },
        ),
      );

      expect(
        AttributedText(
          "Hello, World!",
          AttributedSpans(
            attributions: const [
              SpanMarker(attribution: _bold, offset: 0, markerType: SpanMarkerType.start),
              SpanMarker(attribution: _bold, offset: 5, markerType: SpanMarkerType.end),
            ],
          ),
          {
            5: const _FakePlaceholder("middle"),
          },
        ).removeRegion(startOffset: 3, endOffset: 10),
        AttributedText(
          "Helrld!",
          AttributedSpans(
            attributions: const [
              SpanMarker(attribution: _bold, offset: 0, markerType: SpanMarkerType.start),
              SpanMarker(attribution: _bold, offset: 2, markerType: SpanMarkerType.end),
            ],
          ),
        ),
      );
    });

    group("collapses spans >", () {
      test("when placeholders sit beyond plain text", () {
        final attributedText = AttributedText(
          'Hello world',
          AttributedSpans(
            attributions: [
              const SpanMarker(attribution: ExpectedSpans.bold, offset: 0, markerType: SpanMarkerType.start),
              const SpanMarker(attribution: ExpectedSpans.bold, offset: 11, markerType: SpanMarkerType.end),
              const SpanMarker(attribution: ExpectedSpans.underline, offset: 12, markerType: SpanMarkerType.start),
              const SpanMarker(attribution: ExpectedSpans.underline, offset: 12, markerType: SpanMarkerType.end),
            ],
          ),
          {
            11: const _FakePlaceholder("trailing1"),
            12: const _FakePlaceholder("trailing2"),
          },
        );

        final spans = attributedText.computeAttributionSpans().toList();

        expect(spans.length, 2);

        expect(spans[0].attributions, {ExpectedSpans.bold});
        expect(spans[0].start, 0);
        expect(spans[0].end, 11);

        expect(spans[1].attributions, {ExpectedSpans.underline});
        expect(spans[1].start, 12);
        expect(spans[1].end, 12);
      });
    });
  });
}

const _bold = NamedAttribution("bold");

class _FakePlaceholder {
  const _FakePlaceholder(this.name);

  final String name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is _FakePlaceholder && runtimeType == other.runtimeType && name == other.name;

  @override
  int get hashCode => name.hashCode;
}
