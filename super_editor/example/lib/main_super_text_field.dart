import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor/super_text_field.dart';

/// An app that demos [SuperTextField].
void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _SuperTextFieldDemo(),
    ),
  );
}

const _headingTextStyle = TextStyle(
  fontWeight: FontWeight.bold,
  fontSize: 16,
);

class _SuperTextFieldDemo extends StatefulWidget {
  const _SuperTextFieldDemo();

  @override
  State<_SuperTextFieldDemo> createState() => _SuperTextFieldDemoState();
}

class _SuperTextFieldDemoState extends State<_SuperTextFieldDemo> {
  final _darkBackground = const Color(0xFF222222);
  final _lightBackground = Colors.white;
  final _brightness = ValueNotifier<Brightness>(Brightness.light);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _brightness,
      builder: (context, brightness, child) {
        return Theme(
          data: ThemeData(brightness: brightness),
          child: child!,
        );
      },
      child: Builder(builder: (context) {
        final isLight = Theme.of(context).brightness == Brightness.light;

        return Scaffold(
            appBar: AppBar(
              title: Text('SuperTextField Demo'),
            ),
            body: ColoredBox(
              color: isLight ? _lightBackground : _darkBackground,
              child: Stack(
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 500),
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                        children: [
                          Text(
                            'Single Line SuperTextField',
                            style: _headingTextStyle,
                          ),
                          const SizedBox(height: 8),
                          _SingleLineTextField(),
                          const SizedBox(height: 16),
                          Text(
                            'Multi Line SuperTextField',
                            style: _headingTextStyle,
                          ),
                          const SizedBox(height: 8),
                          _MultiLineTextField(),
                          const SizedBox(height: 16),
                          Text(
                            'Dynamic SuperTextField',
                            style: _headingTextStyle,
                          ),
                          const SizedBox(height: 8),
                          _DynamicTextField(),
                        ],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: ListenableBuilder(
                      listenable: _brightness,
                      builder: (context, child) {
                        return child!;
                      },
                      child: _buildCornerFabs(),
                    ),
                  ),
                ],
              ),
            ));
      }),
    );
  }

  Widget _buildCornerFabs() {
    return Padding(
      padding: const EdgeInsets.only(right: 16, bottom: 16),
      child: _buildLightAndDarkModeToggle(),
    );
  }

  Widget _buildLightAndDarkModeToggle() {
    return FloatingActionButton(
      backgroundColor: _brightness.value == Brightness.light ? _darkBackground : _lightBackground,
      foregroundColor: _brightness.value == Brightness.light ? _lightBackground : _darkBackground,
      elevation: 5,
      onPressed: () {
        _brightness.value = _brightness.value == Brightness.light ? Brightness.dark : Brightness.light;
      },
      child: _brightness.value == Brightness.light
          ? const Icon(
              Icons.dark_mode,
            )
          : const Icon(
              Icons.light_mode,
            ),
    );
  }
}

class _SingleLineTextField extends StatefulWidget {
  const _SingleLineTextField();

  @override
  State<_SingleLineTextField> createState() => _SingleLineTextFieldState();
}

class _SingleLineTextFieldState extends State<_SingleLineTextField> {
  final _focusNode = FocusNode();
  final _textController = ImeAttributedTextEditingController(
    controller: AttributedTextEditingController(),
  );

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return TapRegion(
      groupId: "textfields",
      onTapOutside: (_) => _focusNode.unfocus(),
      child: TextFieldBorder(
        focusNode: _focusNode,
        borderBuilder: _borderBuilder,
        child: SuperTextField(
          focusNode: _focusNode,
          textController: _textController,
          controlsColor: isLight ? Colors.black : Colors.white,
          textStyleBuilder: (_) => _textStyleBuilder(_, isLight),
          hintBuilder: _createHintBuilder("Enter single line text..."),
          padding: const EdgeInsets.all(4),
          minLines: 1,
          maxLines: 1,
          inputSource: TextInputSource.ime,
        ),
      ),
    );
  }
}

class _MultiLineTextField extends StatefulWidget {
  const _MultiLineTextField();

  @override
  State<_MultiLineTextField> createState() => _MultiLineTextFieldState();
}

class _MultiLineTextFieldState extends State<_MultiLineTextField> {
  final _focusNode = FocusNode();
  final _textController = ImeAttributedTextEditingController(
    controller: AttributedTextEditingController(),
  );

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return TapRegion(
      groupId: "textfields",
      onTapOutside: (_) => _focusNode.unfocus(),
      child: TextFieldBorder(
        focusNode: _focusNode,
        borderBuilder: _borderBuilder,
        child: SuperTextField(
          focusNode: _focusNode,
          controlsColor: isLight ? Colors.black : Colors.white,
          textController: _textController,
          textStyleBuilder: (_) => _textStyleBuilder(_, isLight),
          hintBuilder: _createHintBuilder("Type some text..."),
          padding: const EdgeInsets.all(4),
          minLines: 5,
          maxLines: 5,
          inputSource: TextInputSource.ime,
        ),
      ),
    );
  }
}

BoxDecoration _borderBuilder(TextFieldBorderState borderState, {Color? borderColor}) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(4),
    border: Border.all(
      color: borderState.hasError //
          ? Colors.red
          : borderState.hasFocus
              ? Colors.blue
              : (borderColor ?? Colors.grey.shade300),
      width: borderState.hasError ? 2 : 1,
    ),
  );
}

TextStyle _textStyleBuilder(Set<Attribution> attributions, bool isLight) {
  return defaultTextFieldStyleBuilder(attributions).copyWith(
    color: isLight ? Colors.black : Colors.white,
  );
}

WidgetBuilder _createHintBuilder(String hintText) {
  return (BuildContext context) {
    return Text(
      hintText,
      style: TextStyle(color: Colors.grey),
    );
  };
}

class _DynamicTextField extends StatefulWidget {
  const _DynamicTextField({super.key});

  @override
  State<_DynamicTextField> createState() => __DynamicTextFieldState();
}

class __DynamicTextFieldState extends State<_DynamicTextField> {
  final _focusNode = FocusNode();
  final _textController = ImeAttributedTextEditingController(
    controller: AttributedTextEditingController(),
  );
  int _minLines = 1;
  int _maxLines = 1;
  final _formKey = GlobalKey<FormState>();
  final _maxController = TextEditingController(text: '1');
  final _minController = TextEditingController(text: '1');

  Color _borderColor = Colors.grey;

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    _maxController.dispose();
    _minController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TapRegion(
          groupId: "textfields",
          onTapOutside: (_) => _focusNode.unfocus(),
          child: TextFieldBorder(
            focusNode: _focusNode,
            borderBuilder: (_) => _borderBuilder(_, borderColor: _borderColor),
            child: SuperTextField(
              focusNode: _focusNode,
              textController: _textController,
              controlsColor: isLight ? Colors.black : Colors.white,
              textStyleBuilder: (_) => _textStyleBuilder(_, isLight),
              hintBuilder: _createHintBuilder("Enter single line text..."),
              padding: const EdgeInsets.all(4),
              minLines: _minLines,
              maxLines: _maxLines,
              inputSource: TextInputSource.ime,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Change below parameters',
          style: _headingTextStyle,
        ),
        const SizedBox(height: 8),
        Form(
          key: _formKey,
          child: Column(
            children: [
              _linesSelector('Min Lines', _minController),
              const SizedBox(height: 8),
              _linesSelector('Max Lines', _maxController),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Change border color',
          style: _headingTextStyle,
        ),
        const SizedBox(height: 8),
        Wrap(
          children: [Colors.blue, Colors.green, Colors.orange, Colors.red].map((color) => _colorTile(color)).toList(),
        ),
      ],
    );
  }

  Widget _colorTile(Color color) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _borderColor = color;
        });
      },
      child: Container(
        height: 40,
        width: 40,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: color,
      ),
    );
  }

  Row _linesSelector(String title, TextEditingController controller) {
    return Row(
      children: [
        Text(title),
        const SizedBox(width: 8),
        Expanded(
          child: _numberTextField(controller),
        ),
      ],
    );
  }

  TextFormField _numberTextField(TextEditingController controller) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
      ],
      decoration: InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.fromLTRB(8, 4, 8, 4),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.grey),
        ),
      ),
      validator: (userInput) {
        if (userInput == null) {
          return 'Invalid number';
        }

        int value = int.parse(userInput);
        if (value <= 0 || value > 5) {
          return 'Please select a value between (1, 5)';
        }

        int min = int.parse(_minController.text);
        int max = int.parse(_maxController.text);

        if (min > max) {
          return 'Min lines cannot be greater than max lines';
        }

        return null;
      },
      onChanged: (userInput) {
        if (_formKey.currentState!.validate()) {
          setState(() {
            _minLines = int.parse(_minController.text);
            _maxLines = int.parse(_maxController.text);
          });
        }
      },
    );
  }
}
