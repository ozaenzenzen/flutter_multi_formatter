/*
(c) Copyright 2020 Serov Konstantin.

Licensed under the MIT license:

    http://www.opensource.org/licenses/mit-license.php

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'formatter_utils.dart';
import 'phone_input_enums.dart';

class PhoneInputFormatter extends TextInputFormatter {
  final ValueChanged<PhoneCountryData?>? onCountrySelected;
  final bool allowEndlessPhone;
  final String? defaultCountryCode;

  PhoneCountryData? _countryData;
  String _lastValue = '';

  /// [onCountrySelected] when you enter a phone
  /// and a country is detected
  /// this callback gets called
  /// [allowEndlessPhone] if true, a phone can
  /// still be enterng after the whole mask is matched.
  /// use if you are not sure that all masks are supported
  /// [defaultCountryCode] if you set a default country code,
  /// the phone will be formatted according to its country mask
  /// and no leading country code will be present in the masked value
  PhoneInputFormatter({
    this.onCountrySelected,
    this.allowEndlessPhone = false,
    this.defaultCountryCode,
  });

  String get masked => _lastValue;

  String get unmasked => '+${toNumericString(
        _lastValue,
        allowHyphen: false,
        allowAllZeroes: true,
      )}';

  bool get isFilled => isPhoneValid(
        masked,
        defaultCountryCode: defaultCountryCode,
      );

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var isErasing = newValue.text.length < oldValue.text.length;
    _lastValue = newValue.text;

    var onlyNumbers = toNumericString(
      newValue.text,
      allowAllZeroes: true,
    );
    String maskedValue;
    if (isErasing) {
      if (newValue.text.isEmpty) {
        _clearCountry();
      }
    }
    if (onlyNumbers.length == 2) {
      /// ?????? ???????????????????? ?????? ????????????, ???? ???????????? ???????????? ?? ??????????????????
      /// ???????????? ???? ???? 7
      var isRussianWrongNumber =
          onlyNumbers[0] == '8' && onlyNumbers[1] == '9' ||
              onlyNumbers[0] == '8' && onlyNumbers[1] == '3';
      if (isRussianWrongNumber) {
        onlyNumbers = '7${onlyNumbers[1]}';
        _countryData = null;
        _applyMask(
          '7',
          allowEndlessPhone,
        );
      }

      final isAustralianPhoneNumber =
          onlyNumbers[0] == '0' && onlyNumbers[1] == '4';
      if (isAustralianPhoneNumber) {
        onlyNumbers = '61${onlyNumbers[1]}';
        _countryData = null;
        _applyMask('61', allowEndlessPhone);
      }
    }

    maskedValue = _applyMask(onlyNumbers, allowEndlessPhone);
    if (maskedValue == oldValue.text && onlyNumbers != '7') {
      _lastValue = maskedValue;
      if (isErasing) {
        var newSelection = oldValue.selection;
        newSelection = newSelection.copyWith(
          baseOffset: oldValue.selection.baseOffset,
          extentOffset: oldValue.selection.baseOffset,
        );
        return oldValue.copyWith(
          selection: newSelection,
        );
      }
      return oldValue;
    }

    final endOffset = newValue.text.length - newValue.selection.end;
    final selectionEnd = maskedValue.length - endOffset;

    _lastValue = maskedValue;
    return TextEditingValue(
      selection: TextSelection.collapsed(
        offset: selectionEnd,
      ),
      text: maskedValue,
    );
  }

  /// this is a small dirty hask to be able to remove the firt characted
  Future _clearCountry() async {
    await Future.delayed(Duration(milliseconds: 5));
    _updateCountryData(null);
  }

  void _updateCountryData(PhoneCountryData? countryData) {
    _countryData = countryData;
    if (onCountrySelected != null) {
      onCountrySelected!(_countryData);
    }
  }

  String _applyMask(
    String numericString,
    bool allowEndlessPhone,
  ) {
    if (numericString.isEmpty) {
      _updateCountryData(null);
    } else {
      PhoneCountryData? countryData;

      if (defaultCountryCode != null) {
        countryData = PhoneCodes.getPhoneCountryDataByCountryCode(
          defaultCountryCode!,
        );
      } else {
        countryData = PhoneCodes.getCountryDataByPhone(numericString);
      }
      if (countryData != null) {
        _updateCountryData(countryData);
      }
    }
    if (_countryData != null) {
      return _formatByMask(
        numericString,
        _countryData!.getCorrectMask(defaultCountryCode),
        _countryData!.getCorrectAltMasks(defaultCountryCode),
        0,
        allowEndlessPhone,
      );
    }
    return numericString;
  }

  /// adds a list of alternative phone maskes to a country
  /// data. This method can be used if some mask is lacking
  /// [countryCode] must be exactrly 2 uppercase letters like RU, or US
  /// or ES, or DE.
  /// [alternativeMasks] a list of masks like
  /// ['+00 (00) 00000-0000', '+00 (00) 0000-0000'] that will be used
  /// as an alternative. The list might be in any order
  /// [mergeWithExisting] if this is true, new masks will be added to
  /// an existing list. If false, the new list will completely replace the
  /// existing one
  static void addAlternativePhoneMasks({
    required String countryCode,
    required List<String> alternativeMasks,
    bool mergeWithExisting = false,
  }) {
    assert(alternativeMasks.isNotEmpty);
    final countryData = _findCountryDataByCountryCode(countryCode);
    String currentMask = countryData['phoneMask'];
    alternativeMasks.sort((a, b) => a.length.compareTo(b.length));
    countryData['phoneMask'] = alternativeMasks.first;
    alternativeMasks.removeAt(0);
    if (!alternativeMasks.contains(currentMask)) {
      alternativeMasks.add(currentMask);
    }
    alternativeMasks.sort((a, b) => a.length.compareTo(b.length));
    if (!mergeWithExisting || countryData['altMasks'] == null) {
      countryData['altMasks'] = alternativeMasks;
    } else {
      final existingList = countryData['altMasks'];
      alternativeMasks.forEach((m) {
        existingList.add(m);
      });
    }
    // if (kDebugMode) {
    //   print('Alternative masks for country "${countryData['country']}"' +
    //       ' is now ${countryData['altMasks']}');
    // }
  }

  /// Replaces an existing phone mask for the given country
  /// e.g. Russian mask right now is +0 (000) 000-00-00
  /// if you want to replace it by +0 (000) 000 00 00
  /// simply call this method like this
  /// PhoneInputFormatter.replacePhoneMask(
  ///   countryCode: 'RU',
  ///   newMask: '+0 (000) 000 00 00',
  /// );
  static void replacePhoneMask({
    required String countryCode,
    required String newMask,
  }) {
    checkMask(newMask);
    final countryData = _findCountryDataByCountryCode(countryCode);
    var currentMask = countryData['phoneMask'];
    if (currentMask != newMask) {
      print(
        'Phone mask for country "${countryData['country']}"' +
            ' was replaced from $currentMask to $newMask',
      );
      countryData['phoneMask'] = newMask;
    }
  }

  static Map<String, dynamic> _findCountryDataByCountryCode(
    String countryCode,
  ) {
    assert(countryCode.length == 2);
    countryCode = countryCode.toUpperCase();
    var countryData = PhoneCodes._data.firstWhereOrNull(
      ((m) => m['countryCode'] == countryCode),
    );
    if (countryData == null) {
      throw 'A country with a code of $countryCode is not found';
    }
    return countryData;
  }
}

bool isPhoneValid(
  String phone, {
  bool allowEndlessPhone = false,
  String? defaultCountryCode,
}) {
  phone = toNumericString(
    phone,
    allowHyphen: false,
    errorText: null,
    allowAllZeroes: true,
  );
  if (phone.isEmpty) {
    return false;
  }
  PhoneCountryData? countryData;
  if (defaultCountryCode != null) {
    countryData = PhoneCodes.getPhoneCountryDataByCountryCode(
      defaultCountryCode,
    );
  } else {
    countryData = PhoneCodes.getCountryDataByPhone(phone);
  }
  if (countryData == null) {
    return false;
  }
  final cMask = countryData.getCorrectMask(defaultCountryCode);
  final cAltMasks = countryData.getCorrectAltMasks(defaultCountryCode);
  var formatted = _formatByMask(
    phone,
    cMask,
    cAltMasks,
    0,
    allowEndlessPhone,
  );
  final preProcessed = toNumericString(
    formatted,
    allowHyphen: false,
    errorText: null,
    allowAllZeroes: true,
  );
  if (allowEndlessPhone) {
    var contains = phone.contains(preProcessed);
    return contains;
  }
  var correctLength = formatted.length == cMask.length;
  if (correctLength != true && cAltMasks != null) {
    return cAltMasks.any(
      (altMask) => formatted.length == altMask.length,
    );
  }
  return correctLength;
}

/// [allowEndlessPhone] if this is true,
/// the
String? formatAsPhoneNumber(
  String phone, {
  InvalidPhoneAction invalidPhoneAction = InvalidPhoneAction.ShowUnformatted,
  bool allowEndlessPhone = false,
  String? defaultMask,
  String? defaultCountryCode,
}) {
  if (!isPhoneValid(
    phone,
    allowEndlessPhone: allowEndlessPhone,
    defaultCountryCode: defaultCountryCode,
  )) {
    switch (invalidPhoneAction) {
      case InvalidPhoneAction.ShowUnformatted:
        if (defaultMask == null) return phone;
        break;
      case InvalidPhoneAction.ReturnNull:
        return null;
      case InvalidPhoneAction.ShowPhoneInvalidString:
        return 'invalid phone';
    }
  }
  phone = toNumericString(
    phone,
    errorText: null,
    allowAllZeroes: true,
  );
  PhoneCountryData? countryData;
  if (defaultCountryCode != null) {
    countryData = PhoneCodes.getPhoneCountryDataByCountryCode(
      defaultCountryCode,
    );
  } else {
    countryData = PhoneCodes.getCountryDataByPhone(
      phone,
    );
  }

  if (countryData != null) {
    return _formatByMask(
      phone,
      countryData.getCorrectMask(defaultCountryCode),
      countryData.getCorrectAltMasks(defaultCountryCode),
      0,
      allowEndlessPhone,
    );
  } else {
    return _formatByMask(
      phone,
      defaultMask!,
      null,
      0,
      allowEndlessPhone,
    );
  }
}

String _formatByMask(
  String text,
  String mask,
  List<String>? altMasks, [
  int altMaskIndex = 0,
  bool allowEndlessPhone = false,
]) {
  text = toNumericString(
    text,
    allowHyphen: false,
    errorText: null,
    allowAllZeroes: true,
  );
  var result = <String>[];
  var indexInText = 0;
  for (var i = 0; i < mask.length; i++) {
    if (indexInText >= text.length) {
      break;
    }
    var curMaskChar = mask[i];
    if (curMaskChar == '0') {
      var curChar = text[indexInText];
      if (isDigit(curChar)) {
        result.add(curChar);
        indexInText++;
      } else {
        break;
      }
    } else {
      result.add(curMaskChar);
    }
  }

  var actualDigitsInMask = toNumericString(
    mask,
    allowHyphen: true,
    allowPeriod: false,
    errorText: null,
    allowAllZeroes: true,
  ).replaceAll(',', '');
  // print(actualDigitsInMask);
  if (actualDigitsInMask.length < text.length) {
    if (altMasks != null && altMaskIndex < altMasks.length) {
      var formatResult = _formatByMask(
        text,
        altMasks[altMaskIndex],
        altMasks,
        altMaskIndex + 1,
        allowEndlessPhone,
      );
      return formatResult;
    }

    if (allowEndlessPhone) {
      /// if you do not need to restrict the length of phones
      /// by a mask
      result.add(' ');
      for (var i = actualDigitsInMask.length; i < text.length; i++) {
        result.add(text[i]);
      }
    }
  }

  final jointResult = result.join();
  return jointResult;
}

/// returns a list of country datas with a country code of
/// the supplied phone number. The return type is List because
/// many countries and territories may share the same phone code
/// the list will contain one [PhoneCountryData] at max
/// [returns] A list of [PhoneCountryData] datas or an empty list
List<PhoneCountryData> getCountryDatasByPhone(String phone) {
  phone = toNumericString(
    phone,
    allowAllZeroes: true,
  );
  if (phone.isEmpty || phone.length < 11) {
    return <PhoneCountryData>[];
  }
  var phoneCode = phone.substring(0, phone.length - 10);
  return PhoneCodes.getAllCountryDatasByPhoneCode(phoneCode);
}

class PhoneCountryData {
  final String? country;

  /// this field is used to store real phone code
  /// for most countries it will be the same as internalPhoneCode
  /// but there are cases when system need another internal code
  /// to tell apart similar phone code e.g. Russia and Kazakhstan
  /// Kazakhstan has the same code as Russia +7 but internal code is 77
  /// because most phones there start with 77 while in Russia it's 79
  final String? phoneCode;
  final String? internalPhoneCode;
  final String? countryCode;
  final String? phoneMask;

  String? _maskWithoutCountryCode;

  String getCorrectMask(String? countryCode) {
    if (countryCode == null) {
      return phoneMask!;
    }
    return phoneMaskWithoutCountryCode;
  }

  String get phoneMaskWithoutCountryCode {
    if (_maskWithoutCountryCode != null) {
      return _maskWithoutCountryCode!;
    }
    _maskWithoutCountryCode = _trimPhoneCode(
      phoneMask: phoneMask!,
      phoneCode: phoneCode!,
    );
    return _maskWithoutCountryCode!;
  }

  String _trimPhoneCode({
    required String phoneMask,
    required String phoneCode,
  }) {
    final countryCodeLength = phoneCode.length;
    const zero = '0';
    List<String> buffer = [];
    int index = 0;
    for (var i = 0; i < phoneMask.length; i++) {
      final char = phoneMask[i];
      if (index < countryCodeLength) {
        if (char == zero) {
          index++;
          continue;
        }
        if (char == ' ' || char == '+' || char == '(' || char == ')') {
          continue;
        }
      } else {
        buffer.add(char);
      }
    }
    final bufferLength = buffer.length;
    var i = 0;
    while (i < bufferLength) {
      final char = buffer[0];
      if (char == zero || char == '(') {
        break;
      }
      buffer.removeAt(0);
      i++;
    }
    return buffer.join().trim();
  }

  List<String>? getCorrectAltMasks(String? countryCode) {
    if (countryCode == null) {
      return altMasks;
    }
    return altMasksWithoutCountryCodes;
  }

  List<String>? _altMasksWithoutCountryCodes;

  List<String>? get altMasksWithoutCountryCodes {
    if (_altMasksWithoutCountryCodes != null) {
      return _altMasksWithoutCountryCodes;
    }
    _altMasksWithoutCountryCodes = altMasks
            ?.map((e) => _trimPhoneCode(phoneMask: e, phoneCode: phoneCode!))
            .toList() ??
        <String>[];
    return _altMasksWithoutCountryCodes;
  }

  /// this field is used for those countries
  /// there there is more than one possible masks
  /// e.g. Brazil. In most cases this field is null
  /// IMPORTANT! all masks MUST be placed in an ascending order
  /// e.g. the shortest possible mask must be placed in a phoneMask
  /// variable, the longer ones must be in altMasks list starting from
  /// the shortest. That's because they are checked in a direct order
  /// on a user input
  final List<String>? altMasks;

  PhoneCountryData._init({
    this.country,
    this.countryCode,
    this.phoneMask,
    this.altMasks,
    this.phoneCode,
    this.internalPhoneCode,
  });

  String phoneCodeToString() {
    return '+$phoneCode';
  }

  Map<String, dynamic> toMap() {
    return {
      'country': country,
      'internalPhoneCode': internalPhoneCode,
      'phoneCode': phoneCode,
      'countryCode': countryCode,
      'phoneMask': phoneMask,
      'altMasks': altMasks,
    };
  }

  factory PhoneCountryData.fromMap(
    Map value, {
    String lang = '',
  }) {
    final countryData = PhoneCountryData._init(
      country: value['country$lang'],

      /// not all countryDatas need to separate phoneCode and
      /// internalPhoneCode. In most cases they are the same
      /// so we only need to check if the field is present and set
      /// the dafult one if not
      phoneCode: value['phoneCode'] ?? value['internalPhoneCode'],
      internalPhoneCode: value['internalPhoneCode'],
      countryCode: value['countryCode'],
      phoneMask: value['phoneMask'],
      altMasks: value['altMasks'],
    );
    return countryData;
  }

  @override
  String toString() {
    return '[PhoneCountryData(country: $country,' +
        ' phoneCode: $phoneCode, countryCode: $countryCode)]';
  }
}

class PhoneCodes {
  /// ???????????????????? ???????? ?? ???????????? ???????????????? ?????? ????????????, ?????????????? ?? ??????????
  /// ?????????? ?????? ????????, ?????????? ???????? ?????????? setState ?? ?????????????????? ???????????? ????????????
  /// ?????????? ?????????????????? ?????????????????????????????? ??????????????
  static PhoneCountryData? getCountryDataByPhone(
    String phone, {
    int? subscringLength,
  }) {
    if (phone.isEmpty) return null;
    subscringLength = subscringLength ?? phone.length;

    if (subscringLength < 1) return null;
    var phoneCode = phone.substring(0, subscringLength);

    var rawData = _data.firstWhereOrNull(
      (data) =>
          toNumericString(
            data['internalPhoneCode'],
            allowAllZeroes: true,
          ) ==
          phoneCode,
    );
    if (rawData != null) {
      return PhoneCountryData.fromMap(rawData);
    }
    return getCountryDataByPhone(phone, subscringLength: subscringLength - 1);
  }

  static List<PhoneCountryData> getAllCountryDatasByPhoneCode(
    String phoneCode,
  ) {
    phoneCode = phoneCode.replaceAll('+', '');
    var list = <PhoneCountryData>[];
    _data.forEach((data) {
      var c = toNumericString(
        data['internalPhoneCode'],
        allowAllZeroes: true,
      );
      if (c == phoneCode) {
        list.add(PhoneCountryData.fromMap(data));
      }
    });
    return list;
  }

  static List<String>? _countryCodes;

  /// [returns] a list of all available country codes like
  /// ['RU', 'US', 'GB'] etc
  static List<String> getAllCountryCodes() {
    if (_countryCodes == null) {
      _countryCodes = _data.map((e) => e['countryCode'].toString()).toList();
    }
    return _countryCodes!;
  }

  static List<PhoneCountryData>? _allCountryDatas;

  static List<PhoneCountryData> getAllCountryDatas({String langCode = ''}) {
    if (_allCountryDatas == null) {
      _allCountryDatas = _data
          .map((e) => e.containsKey('country${langCode.toUpperCase()}')
              ? PhoneCountryData.fromMap(e, lang: langCode)
              : PhoneCountryData.fromMap(e))
          .toList();
      _allCountryDatas!.sort((a, b) => a.phoneCode!.compareTo(b.phoneCode!));
    }
    return _allCountryDatas!;
  }

  /// Find a PhoneCountryData by a
  /// two-symbol country code like "US" or "RU"
  static PhoneCountryData? getPhoneCountryDataByCountryCode(
    String countryCode,
  ) {
    if (countryCode.length != 2) {
      return null;
    }
    countryCode = countryCode.toUpperCase();
    final Map? countryData = _data.firstWhereOrNull(
      (d) => d['countryCode'] == countryCode,
    );
    if (countryData != null) {
      return PhoneCountryData.fromMap(countryData);
    }
    return null;
  }

  static List<Map<String, dynamic>> _data = <Map<String, dynamic>>[
    {
      'country': 'Afghanistan',
      'countryRU': '????????????????????',
      'internalPhoneCode': '93',
      'countryCode': 'AF',
      'phoneMask': '+00 000 000 0000',
    },
    {
      'country': 'Albania',
      'countryRU': '??????????????',
      'internalPhoneCode': '355',
      'countryCode': 'AL',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Algeria',
      'countryRU': '??????????',
      'internalPhoneCode': '213',
      'countryCode': 'DZ',
      'phoneMask': '+000 0 000 0000',
    },
    {
      'country': 'American Samoa',
      'countryRU': '???????????????????????? ??????????',
      'internalPhoneCode': '1684',
      'countryCode': 'AS',
      'phoneMask': '+0 (000) 000 0000',
    },
    {
      'country': 'Andorra',
      'countryRU': '??????????????',
      'internalPhoneCode': '376',
      'countryCode': 'AD',
      'phoneMask': '+000 000 000 0000',
    },
    {
      'country': 'Angola',
      'countryRU': '????????????',
      'internalPhoneCode': '244',
      'countryCode': 'AO',
      'phoneMask': '+000 0000 000 0000',
    },
    {
      'country': 'Anguilla',
      'countryRU': '??????????????',
      'internalPhoneCode': '1264',
      'countryCode': 'AI',
      'phoneMask': '+0 (000) 000 0000',
    },
    {
      'country': 'Antigua and Barbuda',
      'countryRU': '?????????????? ?? ??????????????',
      'internalPhoneCode': '1268',
      'countryCode': 'AG',
      'phoneMask': '+0 (000) 000 0000',
    },
    {
      'country': 'Argentina',
      'countryRU': '??????????????????',
      'internalPhoneCode': '54',
      'countryCode': 'AR',
      'phoneMask': '+00 0 000 0000',
    },
    {
      'country': 'Armenia',
      'countryRU': '??????????????',
      'internalPhoneCode': '374',
      'countryCode': 'AM',
      'phoneMask': '+000 000 000 0000',
    },
    {
      'country': 'Aruba',
      'countryRU': '??????????',
      'internalPhoneCode': '297',
      'countryCode': 'AW',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Australia',
      'countryRU': '??????????????????',
      'internalPhoneCode': '61',
      'countryCode': 'AU',
      'phoneMask': '+00 0000 0000',
      'altMasks': [
        '+00 0 0000 0000',
      ],
    },
    {
      'country': 'Austria',
      'countryRU': '??????????????',
      'internalPhoneCode': '43',
      'countryCode': 'AT',
      'phoneMask': '+00 000 000 0000',
    },
    {
      'country': 'Azerbaijan',
      'countryRU': '??????????????????????',
      'internalPhoneCode': '994',
      'countryCode': 'AZ',
      'phoneMask': '+000 000 000 0000',
    },
    {
      'country': 'Bahamas',
      'countryRU': '?????????????????? ??????????????',
      'internalPhoneCode': '1242',
      'countryCode': 'BS',
      'phoneMask': '+0 (000) 000 0000',
    },
    {
      'country': 'Bahrain',
      'countryRU': '??????????????',
      'internalPhoneCode': '973',
      'countryCode': 'BH',
      'phoneMask': '+000 000 000 0000',
    },
    {
      'country': 'Bangladesh',
      'countryRU': '??????????????????',
      'internalPhoneCode': '880',
      'countryCode': 'BD',
      'phoneMask': '+000 000 000 0000',
    },
    {
      'country': 'Barbados',
      'countryRU': '????????????????',
      'internalPhoneCode': '1246',
      'countryCode': 'BB',
      'phoneMask': '+0 (000) 000 0000',
    },
    {
      'country': 'Belarus',
      'countryRU': '????????????????',
      'internalPhoneCode': '375',
      'countryCode': 'BY',
      'phoneMask': '+000 (00) 000-00-00',
    },
    {
      'country': 'Belgium',
      'countryRU': '??????????????',
      'internalPhoneCode': '32',
      'countryCode': 'BE',
      'phoneMask': '+00 000 00 00 00',
    },
    {
      'country': 'Belize',
      'countryRU': '??????????',
      'internalPhoneCode': '501',
      'countryCode': 'BZ',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Benin',
      'countryRU': '??????????',
      'internalPhoneCode': '229',
      'countryCode': 'BJ',
      'phoneMask': '+000 000 000 0000',
    },
    {
      'country': 'Bermuda',
      'countryRU': '??????????????',
      'internalPhoneCode': '1441',
      'countryCode': 'BM',
      'phoneMask': '+0 (000) 000 0000',
    },
    {
      'country': 'Bhutan',
      'countryRU': '??????????',
      'internalPhoneCode': '975',
      'countryCode': 'BT',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Bosnia and Herzegovina',
      'countryRU': '???????????? ?? ??????????????????????',
      'internalPhoneCode': '387',
      'countryCode': 'BA',
      'phoneMask': '+000 000 000 0000',
    },
    {
      'country': 'Botswana',
      'countryRU': '????????????????',
      'internalPhoneCode': '267',
      'countryCode': 'BW',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Brazil',
      'countryRU': '????????????????',
      'internalPhoneCode': '55',
      'countryCode': 'BR',
      'phoneMask': '+00 (00) 0000-0000',
      'altMasks': [
        '+00 (00) 00000-0000',
      ],
    },
    {
      'country': 'British Indian Ocean Territory',
      'countryRU': '???????????????????? ???????????????????? ?? ?????????????????? ????????????',
      'internalPhoneCode': '246',
      'countryCode': 'IO',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Bulgaria',
      'countryRU': '????????????????',
      'internalPhoneCode': '359',
      'countryCode': 'BG',
      'phoneMask': '+000 0 000 0000',
    },
    {
      'country': 'Burkina Faso',
      'countryRU': '??????????????-????????',
      'internalPhoneCode': '226',
      'countryCode': 'BF',
      'phoneMask': '+000 0 000 0000',
    },
    {
      'country': 'Burundi',
      'countryRU': '??????????????',
      'internalPhoneCode': '257',
      'countryCode': 'BI',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Cambodia',
      'countryRU': '????????????????',
      'internalPhoneCode': '855',
      'countryCode': 'KH',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Cameroon',
      'countryRU': '??????????????',
      'internalPhoneCode': '237',
      'countryCode': 'CM',
      'phoneMask': '+000 0 000 0000',
    },
    {
      'country': 'United States',
      'countryRU': '??????',
      'internalPhoneCode': '1',
      'countryCode': 'US',
      'phoneMask': '+0 (000) 000 0000',
    },
    {
      'country': 'Canada',
      'countryRU': '????????????',
      'internalPhoneCode': '1',
      'countryCode': 'CA',
      'phoneMask': '+0 (000) 000 0000',
    },
    {
      'country': 'Cape Verde',
      'countryRU': '????????-??????????',
      'internalPhoneCode': '238',
      'countryCode': 'CV',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Cayman Islands',
      'countryRU': '?????????????????? ??????????????',
      'internalPhoneCode': '345',
      'countryCode': 'KY',
      'phoneMask': '+0 (000) 000 0000',
    },
    {
      'country': 'Central African Republic',
      'countryRU': '?????????????????????????????????????????? ????????????????????',
      'internalPhoneCode': '236',
      'countryCode': 'CF',
      'phoneMask': '+000 0 000 0000',
    },
    {
      'country': 'Chad',
      'countryRU': '??????',
      'internalPhoneCode': '235',
      'countryCode': 'TD',
      'phoneMask': '+000 0 000 0000',
    },
    {
      'country': 'Chile',
      'countryRU': '????????',
      'internalPhoneCode': '56',
      'countryCode': 'CL',
      'phoneMask': '+00 00 000 0000',
    },
    {
      'country': 'China',
      'countryRU': '??????????',
      'internalPhoneCode': '86',
      'countryCode': 'CN',
      'phoneMask': '+00 000 0000 0000',
    },
    {
      'country': 'Christmas Island',
      'countryRU': '???????????? ??????????????????',
      'internalPhoneCode': '61',
      'countryCode': 'CX',
      'phoneMask': '+00 0 0000 0000',
    },
    {
      'country': 'Colombia',
      'countryRU': '????????????????',
      'internalPhoneCode': '57',
      'countryCode': 'CO',
      'phoneMask': '+00 000 000 0000',
    },
    {
      'country': 'Comoros',
      'countryRU': '?????????????????? ??????????????',
      'internalPhoneCode': '269',
      'countryCode': 'KM',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Congo',
      'countryRU': '??????????',
      'internalPhoneCode': '242',
      'countryCode': 'CG',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Cook Islands',
      'countryRU': '?????????????? ????????',
      'internalPhoneCode': '682',
      'countryCode': 'CK',
      'phoneMask': '+682 00 000',
    },
    {
      'country': 'Costa Rica',
      'countryRU': '??????????-????????',
      'internalPhoneCode': '506',
      'countryCode': 'CR',
      'phoneMask': '+000 0 000 0000',
    },
    {
      'country': 'Croatia',
      'countryRU': '????????????????',
      'internalPhoneCode': '385',
      'countryCode': 'HR',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Cuba',
      'countryRU': '????????',
      'internalPhoneCode': '53',
      'countryCode': 'CU',
      'phoneMask': '+00 000 000 0000',
    },
    {
      'country': 'Cyprus',
      'countryRU': '????????',
      'internalPhoneCode': '357',
      'countryCode': 'CY',
      'phoneMask': '+000 0 000 0000',
    },
    {
      'country': 'Czech Republic',
      'countryRU': '?????????????? ????????????????????',
      'internalPhoneCode': '420',
      'countryCode': 'CZ',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Denmark',
      'countryRU': '??????????',
      'internalPhoneCode': '45',
      'countryCode': 'DK',
      'phoneMask': '+00 0 000 0000',
    },
    {
      'country': 'Djibouti',
      'countryRU': '??????????????',
      'internalPhoneCode': '253',
      'countryCode': 'DJ',
      'phoneMask': '+000 0 000 0000',
    },
    {
      'country': 'Dominica',
      'countryRU': '????????????????',
      'internalPhoneCode': '1767',
      'countryCode': 'DM',
      'phoneMask': '+0000 000 0000',
    },
    {
      'country': 'Dominican Republic',
      'countryRU': '?????????????????????????? ????????????????????',
      'internalPhoneCode': '1809',
      'countryCode': 'DO',
      'phoneMask': '+0000 000 0000',
    },
    {
      'country': 'Ecuador',
      'countryRU': '??????????????',
      'internalPhoneCode': '593',
      'countryCode': 'EC',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Egypt',
      'countryRU': '????????????',
      'internalPhoneCode': '20',
      'countryCode': 'EG',
      'phoneMask': '+00 000 000 0000',
    },
    {
      'country': 'El Salvador',
      'countryRU': '??????????????????',
      'internalPhoneCode': '503',
      'countryCode': 'SV',
      'phoneMask': '+000 00 0000 0000',
    },
    {
      'country': 'Equatorial Guinea',
      'countryRU': '???????????????????????????? ????????????',
      'internalPhoneCode': '240',
      'countryCode': 'GQ',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Eritrea',
      'countryRU': '??????????????',
      'internalPhoneCode': '291',
      'countryCode': 'ER',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Estonia',
      'countryRU': '??????????????',
      'internalPhoneCode': '372',
      'countryCode': 'EE',
      'phoneMask': '+000 000 000',
      'altMasks': [
        '+000 000 0000',
        '+000 0000 0000',
        '+000 000000000',
      ]
    },
    {
      'country': 'Ethiopia',
      'countryRU': '??????????????',
      'internalPhoneCode': '251',
      'countryCode': 'ET',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Faroe Islands',
      'countryRU': '?????????????????? ??????????????',
      'internalPhoneCode': '298',
      'countryCode': 'FO',
      'phoneMask': '+000 000000',
    },
    {
      'country': 'Fiji',
      'countryRU': '??????????',
      'internalPhoneCode': '679',
      'countryCode': 'FJ',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Finland',
      'countryRU': '??????????????????',
      'internalPhoneCode': '358',
      'countryCode': 'FI',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'France',
      'countryRU': '??????????????',
      'internalPhoneCode': '33',
      'countryCode': 'FR',
      'phoneMask': '+00 0 00 00 00 00',
    },
    {
      'country': 'French Guiana',
      'countryRU': '?????????????????????? ????????????',
      'internalPhoneCode': '594',
      'countryCode': 'GF',
      'phoneMask': '+000 000 00 00 00',
    },
    {
      'country': 'French Polynesia',
      'countryRU': '?????????????????????? ??????????????????',
      'internalPhoneCode': '689',
      'countryCode': 'PF',
      'phoneMask': '+000 000000',
    },
    {
      'country': 'Gabon',
      'countryRU': '??????????',
      'internalPhoneCode': '241',
      'countryCode': 'GA',
      'phoneMask': '+000 000000',
    },
    {
      'country': 'Gambia',
      'countryRU': '????????????',
      'internalPhoneCode': '220',
      'countryCode': 'GM',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Georgia',
      'countryRU': '????????????',
      'internalPhoneCode': '995',
      'countryCode': 'GE',
      'phoneMask': '+000 000 000000',
    },
    {
      'country': 'Germany',
      'countryRU': '????????????????',
      'internalPhoneCode': '49',
      'countryCode': 'DE',
      'phoneMask': '+00 00 000000000',
    },
    {
      'country': 'Ghana',
      'countryRU': '????????',
      'internalPhoneCode': '233',
      'countryCode': 'GH',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Gibraltar',
      'countryRU': '??????????????????',
      'internalPhoneCode': '350',
      'countryCode': 'GI',
      'phoneMask': '+000 00000',
    },
    {
      'country': 'Greece',
      'countryRU': '????????????',
      'internalPhoneCode': '30',
      'countryCode': 'GR',
      'phoneMask': '+00 0 000 0000',
    },
    {
      'country': 'Greenland',
      'countryRU': '????????????????????',
      'internalPhoneCode': '299',
      'countryCode': 'GL',
      'phoneMask': '+000 000000',
    },
    {
      'country': 'Grenada',
      'countryRU': '??????????????',
      'internalPhoneCode': '1473',
      'countryCode': 'GD',
      'phoneMask': '+0 (000) 000 0000',
    },
    {
      'country': 'Guadeloupe',
      'countryRU': '??????????????????',
      'internalPhoneCode': '590',
      'countryCode': 'GP',
      'phoneMask': '+000 000 00 00 00',
    },
    {
      'country': 'Guam',
      'countryRU': '????????',
      'internalPhoneCode': '1671',
      'countryCode': 'GU',
      'phoneMask': '+0 (000) 000 0000',
    },
    {
      'country': 'Guatemala',
      'countryRU': '??????????????????',
      'internalPhoneCode': '502',
      'countryCode': 'GT',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Guinea',
      'countryRU': '????????????',
      'internalPhoneCode': '224',
      'countryCode': 'GN',
      'phoneMask': '+000 000 000000',
    },
    {
      'country': 'Guinea-Bissau',
      'countryRU': '????????????-??????????',
      'internalPhoneCode': '245',
      'countryCode': 'GW',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Guyana',
      'countryRU': '????????????',
      'internalPhoneCode': '592',
      'countryCode': 'GY',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Haiti',
      'countryRU': '??????????',
      'internalPhoneCode': '509',
      'countryCode': 'HT',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Honduras',
      'countryRU': '????????????????',
      'internalPhoneCode': '504',
      'countryCode': 'HN',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Hungary',
      'countryRU': '??????????????',
      'internalPhoneCode': '36',
      'countryCode': 'HU',
      'phoneMask': '+00 0 000 0000',
      'altMasks': [
        '+00 00 000 0000',
      ],
    },
    {
      'country': 'Hungary (Alternative)',
      'countryRU': '?????????????? (????????????????????????)',
      'internalPhoneCode': '06',
      'countryCode': 'HU',
      'phoneMask': '+00 0 000 0000',
      'altMasks': [
        '+00 00 000 0000',
      ],
    },
    {
      'country': 'Iceland',
      'countryRU': '????????????????',
      'internalPhoneCode': '354',
      'countryCode': 'IS',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'India',
      'countryRU': '??????????',
      'internalPhoneCode': '91',
      'countryCode': 'IN',
      'phoneMask': '+00 000 000 0000',
    },
    {
      'country': 'Indonesia',
      'countryRU': '??????????????????',
      'internalPhoneCode': '62',
      'countryCode': 'ID',
      'phoneMask': '+00 00 0000 0000',
    },
    {
      'country': 'Iraq',
      'countryRU': '????????',
      'internalPhoneCode': '964',
      'countryCode': 'IQ',
      'phoneMask': '+000 (00) 000 00000',
    },
    {
      'country': 'Ireland',
      'countryRU': '????????????????',
      'internalPhoneCode': '353',
      'countryCode': 'IE',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Israel',
      'countryRU': '??????????????',
      'internalPhoneCode': '972',
      'countryCode': 'IL',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Italy',
      'countryRU': '????????????',
      'internalPhoneCode': '39',
      'countryCode': 'IT',
      'phoneMask': '+00 00 000 0000',
    },
    {
      'country': 'Jamaica',
      'countryRU': '????????????',
      'internalPhoneCode': '1876',
      'countryCode': 'JM',
      'phoneMask': '+0 (000) 000 0000',
    },
    {
      'country': 'Japan',
      'countryRU': '????????????',
      'internalPhoneCode': '81',
      'countryCode': 'JP',
      'phoneMask': '+00 00 000 0000',
    },
    {
      'country': 'Jordan',
      'countryRU': '??????????????',
      'internalPhoneCode': '962',
      'countryCode': 'JO',
      'phoneMask': '+000 0 000 0000',
    },
    {
      'country': 'Kazakhstan',
      'countryRU': '??????????????????',
      'internalPhoneCode': '77',
      'phoneCode': '7',
      'countryCode': 'KZ',
      'phoneMask': '+0 (000) 000 0000',
    },
    {
      'country': 'Kenya',
      'countryRU': '??????????',
      'internalPhoneCode': '254',
      'countryCode': 'KE',
      'phoneMask': '+000 000 000000',
    },
    {
      'country': 'Kiribati',
      'countryRU': '????????????????',
      'internalPhoneCode': '686',
      'countryCode': 'KI',
      'phoneMask': '+000 00000',
    },
    {
      'country': 'Kuwait',
      'countryRU': '????????????',
      'internalPhoneCode': '965',
      'countryCode': 'KW',
      'phoneMask': '+000 0000 0000',
    },
    {
      'country': 'Kyrgyzstan',
      'countryRU': '????????????????????',
      'internalPhoneCode': '996',
      'countryCode': 'KG',
      'phoneMask': '+000 000 000000',
    },
    {
      'country': 'Latvia',
      'countryRU': '????????????',
      'internalPhoneCode': '371',
      'countryCode': 'LV',
      'phoneMask': '+000 0000 0000',
    },
    {
      'country': 'Lebanon',
      'countryRU': '??????????',
      'internalPhoneCode': '961',
      'countryCode': 'LB',
      'phoneMask': '+000 00 000 000',
    },
    {
      'country': 'Lesotho',
      'countryRU': '????????????',
      'internalPhoneCode': '266',
      'countryCode': 'LS',
      'phoneMask': '+000 0000 0000',
    },
    {
      'country': 'Liberia',
      'countryRU': '??????????????',
      'internalPhoneCode': '231',
      'countryCode': 'LR',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Liechtenstein',
      'countryRU': '??????????????????????',
      'internalPhoneCode': '423',
      'countryCode': 'LI',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Lithuania',
      'countryRU': '??????????',
      'internalPhoneCode': '370',
      'countryCode': 'LT',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Luxembourg',
      'countryRU': '????????????????????',
      'internalPhoneCode': '352',
      'countryCode': 'LU',
      'phoneMask': '+000 000000',
    },
    {
      'country': 'Madagascar',
      'countryRU': '????????????????????',
      'internalPhoneCode': '261',
      'countryCode': 'MG',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Malawi',
      'countryRU': '????????????',
      'internalPhoneCode': '265',
      'countryCode': 'MW',
      'phoneMask': '+000 000000000',
    },
    {
      'country': 'Malaysia',
      'countryRU': '??????????????',
      'internalPhoneCode': '60',
      'countryCode': 'MY',
      'phoneMask': '+00 0 000 0000',
    },
    {
      'country': 'Maldives',
      'countryRU': '????????????????',
      'internalPhoneCode': '960',
      'countryCode': 'MV',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Mali',
      'countryRU': '????????',
      'internalPhoneCode': '223',
      'countryCode': 'ML',
      'phoneMask': '+000 0000 0000',
    },
    {
      'country': 'Malta',
      'countryRU': '????????????',
      'internalPhoneCode': '356',
      'countryCode': 'MT',
      'phoneMask': '+000 0000 0000',
    },
    {
      'country': 'Marshall Islands',
      'countryRU': '?????????????????? ??????????????',
      'internalPhoneCode': '692',
      'countryCode': 'MH',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Martinique',
      'countryRU': '??????????????????',
      'internalPhoneCode': '596',
      'countryCode': 'MQ',
      'phoneMask': '+000 000 00 00 00',
    },
    {
      'country': 'Mauritania',
      'countryRU': '????????????????????',
      'internalPhoneCode': '222',
      'countryCode': 'MR',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Mauritius',
      'countryRU': '????????????????',
      'internalPhoneCode': '230',
      'countryCode': 'MU',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Mayotte',
      'countryRU': '??????????????',
      'internalPhoneCode': '262',
      'countryCode': 'YT',
      'phoneMask': '+000 000 00 00 00',
    },
    {
      'country': 'Mexico',
      'countryRU': '????????????',
      'internalPhoneCode': '52',
      'countryCode': 'MX',
      'phoneMask': '+00 000 000 0000',
    },
    {
      'country': 'Monaco',
      'countryRU': '????????????',
      'internalPhoneCode': '377',
      'countryCode': 'MC',
      'phoneMask': '+000 0000 0000',
    },
    {
      'country': 'Mongolia',
      'countryRU': '????????????????',
      'internalPhoneCode': '976',
      'countryCode': 'MN',
      'phoneMask': '+000 00 000000',
    },
    {
      'country': 'Montenegro',
      'countryRU': '????????????????????',
      'internalPhoneCode': '382',
      'countryCode': 'ME',
      'phoneMask': '+000 00 000000',
    },
    {
      'country': 'Montserrat',
      'countryRU': '????????????????????',
      'internalPhoneCode': '1664',
      'countryCode': 'MS',
      'phoneMask': '+0 (000) 000 0000',
    },
    {
      'country': 'Morocco',
      'countryRU': '??????????????',
      'internalPhoneCode': '212',
      'countryCode': 'MA',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Myanmar',
      'countryRU': '????????????',
      'internalPhoneCode': '95',
      'countryCode': 'MM',
      'phoneMask': '+00 00 000 0000',
    },
    {
      'country': 'Namibia',
      'countryRU': '??????????????',
      'internalPhoneCode': '264',
      'countryCode': 'NA',
      'phoneMask': '+000 00 000000',
    },
    {
      'country': 'Nauru',
      'countryRU': '??????????',
      'internalPhoneCode': '674',
      'countryCode': 'NR',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Nepal',
      'countryRU': '??????????',
      'internalPhoneCode': '977',
      'countryCode': 'NP',
      'phoneMask': '+000 000 000 0000',
    },
    {
      'country': 'Netherlands',
      'countryRU': '????????????????????',
      'internalPhoneCode': '31',
      'countryCode': 'NL',
      'phoneMask': '+00 00 000 0000',
    },
    {
      'country': 'Netherlands Antilles',
      'countryRU': '?????????????????????????? ???????????????????? ??????????????',
      'internalPhoneCode': '599',
      'countryCode': 'AN',
      'phoneMask': '+000 00000000',
    },
    {
      'country': 'New Caledonia',
      'countryRU': '?????????? ??????????????????',
      'internalPhoneCode': '687',
      'countryCode': 'NC',
      'phoneMask': '+000 000000',
    },
    {
      'country': 'New Zealand',
      'countryRU': '?????????? ????????????????',
      'internalPhoneCode': '64',
      'countryCode': 'NZ',
      'phoneMask': '+00 (0) 000 0000',
      'altMasks': [
        '+00 (00) 000 0000',
        '+00 (000) 000 0000',
      ],
    },
    {
      'country': 'Nicaragua',
      'countryRU': '??????????????????',
      'internalPhoneCode': '505',
      'countryCode': 'NI',
      'phoneMask': '+000 0000 0000',
    },
    {
      'country': 'Niger',
      'countryRU': '??????????',
      'internalPhoneCode': '227',
      'countryCode': 'NE',
      'phoneMask': '+000 00 000000',
    },
    {
      'country': 'Nigeria',
      'countryRU': '??????????????',
      'internalPhoneCode': '234',
      'countryCode': 'NG',
      'phoneMask': '+000 000 000 0000',
    },
    {
      'country': 'Niue',
      'countryRU': '????????',
      'internalPhoneCode': '683',
      'countryCode': 'NU',
      'phoneMask': '+000 0000000',
    },
    {
      'country': 'Norfolk Island',
      'countryRU': '???????????? ??????????????',
      'internalPhoneCode': '672',
      'countryCode': 'NF',
      'phoneMask': '+000 0 00 000',
    },
    {
      'country': 'Northern Mariana Islands',
      'countryRU': '???????????????? ???????????????????? ??????????????',
      'internalPhoneCode': '1670',
      'countryCode': 'MP',
      'phoneMask': '+0 (000) 000 0000',
    },
    {
      'country': 'Norway',
      'countryRU': '????????????????',
      'internalPhoneCode': '47',
      'countryCode': 'NO',
      'phoneMask': '+00 0000 0000',
    },
    {
      'country': 'Oman',
      'countryRU': '????????',
      'internalPhoneCode': '968',
      'countryCode': 'OM',
      'phoneMask': '+000 0000 0000',
    },
    {
      'country': 'Pakistan',
      'countryRU': '????????????????',
      'internalPhoneCode': '92',
      'countryCode': 'PK',
      'phoneMask': '+00 000 0000000',
    },
    {
      'country': 'Palau',
      'countryRU': '??????????',
      'internalPhoneCode': '680',
      'countryCode': 'PW',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Panama',
      'countryRU': '????????????',
      'internalPhoneCode': '507',
      'countryCode': 'PA',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Papua New Guinea',
      'countryRU': '??????????-?????????? ????????????',
      'internalPhoneCode': '675',
      'countryCode': 'PG',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Paraguay',
      'countryRU': '????????????????',
      'internalPhoneCode': '595',
      'countryCode': 'PY',
      'phoneMask': '+000 000 000000',
    },
    {
      'country': 'Peru',
      'countryRU': '????????',
      'internalPhoneCode': '51',
      'countryCode': 'PE',
      'phoneMask': '+00 00 000000000',
    },
    {
      'country': 'Philippines',
      'countryRU': '????????????????',
      'internalPhoneCode': '63',
      'countryCode': 'PH',
      'phoneMask': '+00 00 000 0000',
    },
    {
      'country': 'Poland',
      'countryRU': '????????????',
      'internalPhoneCode': '48',
      'countryCode': 'PL',
      'phoneMask': '+00 00 000 0000',
    },
    {
      'country': 'Portugal',
      'countryRU': '????????????????????',
      'internalPhoneCode': '351',
      'countryCode': 'PT',
      'phoneMask': '+000 000 000 000',
    },
    {
      'country': 'Puerto Rico',
      'countryRU': '????????????-????????',
      'internalPhoneCode': '1939',
      'countryCode': 'PR',
      'phoneMask': '+0000 000 0000',
    },
    {
      'country': 'Qatar',
      'countryRU': '??????????',
      'internalPhoneCode': '974',
      'countryCode': 'QA',
      'phoneMask': '+000 0000 0000',
    },
    {
      'country': 'Romania',
      'countryRU': '??????????????',
      'internalPhoneCode': '40',
      'countryCode': 'RO',
      'phoneMask': '+00 000 000 000',
    },
    {
      'country': 'Rwanda',
      'countryRU': '????????????',
      'internalPhoneCode': '250',
      'countryCode': 'RW',
      'phoneMask': '000 000 000',
    },
    {
      'country': 'Samoa',
      'countryRU': '??????????',
      'internalPhoneCode': '685',
      'countryCode': 'WS',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'San Marino',
      'countryRU': '??????-????????????',
      'internalPhoneCode': '378',
      'countryCode': 'SM',
      'phoneMask': '+000 0000 000000',
    },
    {
      'country': 'Saudi Arabia',
      'countryRU': '???????????????????? ????????????',
      'internalPhoneCode': '966',
      'countryCode': 'SA',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Senegal',
      'countryRU': '??????????????',
      'internalPhoneCode': '221',
      'countryCode': 'SN',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Serbia',
      'countryRU': '????????????',
      'internalPhoneCode': '381',
      'countryCode': 'RS',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Seychelles',
      'countryRU': '?????????????????????? ??????????????',
      'internalPhoneCode': '248',
      'countryCode': 'SC',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Sierra Leone',
      'countryRU': '????????????-??????????',
      'internalPhoneCode': '232',
      'countryCode': 'SL',
      'phoneMask': '+000 00 000000',
    },
    {
      'country': 'Singapore',
      'countryRU': '????????????????',
      'internalPhoneCode': '65',
      'countryCode': 'SG',
      'phoneMask': '+00 0000 0000',
    },
    {
      'country': 'Slovakia',
      'countryRU': '????????????????',
      'internalPhoneCode': '421',
      'countryCode': 'SK',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Slovenia',
      'countryRU': '????????????????',
      'internalPhoneCode': '386',
      'countryCode': 'SI',
      'phoneMask': '+000 0 000 00 00',
    },
    {
      'country': 'Solomon Islands',
      'countryRU': '???????????????????? ??????????????',
      'internalPhoneCode': '677',
      'countryCode': 'SB',
      'phoneMask': '+000 00000',
    },
    {
      'country': 'South Africa',
      'countryRU': '?????????? ????????????',
      'internalPhoneCode': '27',
      'countryCode': 'ZA',
      'phoneMask': '+00 00 000 0000',
    },
    {
      'country': 'South Georgia and the South Sandwich Islands',
      'countryRU': '?????????? ?????????????? ?? ?????????? ???????????????????? ??????????????',
      'internalPhoneCode': '500',
      'countryCode': 'GS',
      'phoneMask': '+000 00000',
    },
    {
      'country': 'Spain',
      'countryRU': '??????????????',
      'internalPhoneCode': '34',
      'countryCode': 'ES',
      'phoneMask': '+00 000 000 000',
    },
    {
      'country': 'Sri Lanka',
      'countryRU': '??????-??????????',
      'internalPhoneCode': '94',
      'countryCode': 'LK',
      'phoneMask': '+00 00 000 0000',
    },
    {
      'country': 'Sudan',
      'countryRU': '??????????',
      'internalPhoneCode': '249',
      'countryCode': 'SD',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Suriname',
      'countryRU': '??????????????',
      'internalPhoneCode': '597',
      'countryCode': 'SR',
      'phoneMask': '+000 000000',
    },
    {
      'country': 'Swaziland',
      'countryRU': '??????????????????',
      'internalPhoneCode': '268',
      'countryCode': 'SZ',
      'phoneMask': '+000 0 000 0000',
    },
    {
      'country': 'Sweden',
      'countryRU': '????????????',
      'internalPhoneCode': '46',
      'countryCode': 'SE',
      'phoneMask': '+00 00 000 0000',
    },
    {
      'country': 'Switzerland',
      'countryRU': '??????????????????',
      'internalPhoneCode': '41',
      'countryCode': 'CH',
      'phoneMask': '+00 00 000 0000',
    },
    {
      'country': 'Tajikistan',
      'countryRU': '??????????????????????',
      'internalPhoneCode': '992',
      'countryCode': 'TJ',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Thailand',
      'countryRU': '??????????????',
      'internalPhoneCode': '66',
      'countryCode': 'TH',
      'phoneMask': '+00 0 000 0000',
    },
    {
      'country': 'Togo',
      'countryRU': '????????',
      'internalPhoneCode': '228',
      'countryCode': 'TG',
      'phoneMask': '+000 0 000 0000',
    },
    {
      'country': 'Tokelau',
      'countryRU': '??????????????',
      'internalPhoneCode': '690',
      'countryCode': 'TK',
      'phoneMask': '+000 0000',
    },
    {
      'country': 'Tonga',
      'countryRU': '??????????',
      'internalPhoneCode': '676',
      'countryCode': 'TO',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Trinidad and Tobago',
      'countryRU': '???????????????? ?? ????????????',
      'internalPhoneCode': '1868',
      'countryCode': 'TT',
      'phoneMask': '+0 (000) 000 0000',
    },
    {
      'country': 'Tunisia',
      'countryRU': '??????????',
      'internalPhoneCode': '216',
      'countryCode': 'TN',
      'phoneMask': '+000 0000 0000',
    },
    {
      'country': 'Turkey',
      'countryRU': '????????????',
      'internalPhoneCode': '90',
      'countryCode': 'TR',
      'phoneMask': '+00 000 000 0000',
    },
    {
      'country': 'Turkmenistan',
      'countryRU': '????????????????????????',
      'internalPhoneCode': '993',
      'countryCode': 'TM',
      'phoneMask': '+000 00 000000',
    },
    {
      'country': 'Turks and Caicos Islands',
      'countryRU': '?????????????? ?????????? ?? ????????????',
      'internalPhoneCode': '1649',
      'countryCode': 'TC',
      'phoneMask': '+0 (000) 000 0000',
    },
    {
      'country': 'Tuvalu',
      'countryRU': '????????????',
      'internalPhoneCode': '688',
      'countryCode': 'TV',
      'phoneMask': '+000 00000',
    },
    {
      'country': 'Uganda',
      'countryRU': '????????????',
      'internalPhoneCode': '256',
      'countryCode': 'UG',
      'phoneMask': '+000 000 000000',
    },
    {
      'country': 'Ukraine',
      'countryRU': '??????????????',
      'internalPhoneCode': '380',
      'countryCode': 'UA',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'United Arab Emirates',
      'countryRU': '???????????????????????? ???????????????? ??????????????',
      'internalPhoneCode': '971',
      'countryCode': 'AE',
      'phoneMask': '+000 00 000000',
      'altMasks': [
        '+000 00 0000000',
      ],
    },
    {
      'country': 'United Kingdom',
      'countryRU': '????????????????????????????',
      'internalPhoneCode': '44',
      'countryCode': 'GB',
      'phoneMask': '+00 0000 000000',
    },
    {
      'country': 'Uruguay',
      'countryRU': '??????????????',
      'internalPhoneCode': '598',
      'countryCode': 'UY',
      'phoneMask': '+000 0000 0000',
    },
    {
      'country': 'Uzbekistan',
      'countryRU': '????????????????????',
      'internalPhoneCode': '998',
      'countryCode': 'UZ',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Vanuatu',
      'countryRU': '??????????????',
      'internalPhoneCode': '678',
      'countryCode': 'VU',
      'phoneMask': '+000 00000',
    },
    {
      'country': 'Wallis and Futuna',
      'countryRU': '???????????? ?? ????????????',
      'internalPhoneCode': '681',
      'countryCode': 'WF',
      'phoneMask': '+000 00 0000',
    },
    {
      'country': 'Yemen',
      'countryRU': '??????????',
      'internalPhoneCode': '967',
      'countryCode': 'YE',
      'phoneMask': '+000 0 000000',
    },
    {
      'country': 'Zambia',
      'countryRU': '????????????',
      'internalPhoneCode': '260',
      'countryCode': 'ZM',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Zimbabwe',
      'countryRU': '??????????????',
      'internalPhoneCode': '263',
      'countryCode': 'ZW',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Land Islands',
      'countryRU': '?????????????? ????????',
      'internalPhoneCode': '354',
      'countryCode': 'AX',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Bolivia, Plurinational State of',
      'countryRU': '??????????????, ?????????????????????????????????? ??????????????????????',
      'internalPhoneCode': '591',
      'countryCode': 'BO',
      'phoneMask': '+000 000 000 0000',
    },
    {
      'country': 'Brunei Darussalam',
      'countryRU': '????????????-????????????????????',
      'internalPhoneCode': '673',
      'countryCode': 'BN',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Cocos (Keeling) Islands',
      'countryRU': '?????????????????? (????????????) ??????????????',
      'internalPhoneCode': '61',
      'countryCode': 'CC',
      'phoneMask': '+00 0 0000 0000',
    },
    {
      'country': 'Congo, The Democratic Republic of the',
      'countryRU': '??????????, ?????????????????????????????? ????????????????????',
      'internalPhoneCode': '243',
      'countryCode': 'CD',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Cote d\'Ivoire',
      'countryRU': '??????-??\'????????????',
      'internalPhoneCode': '225',
      'countryCode': 'CI',
      'phoneMask': '+000 00000000',
    },
    {
      'country': 'Falkland Islands (Malvinas)',
      'countryRU': '???????????????????????? (??????????????????????) ??????????????',
      'internalPhoneCode': '500',
      'countryCode': 'FK',
      'phoneMask': '+000 00000',
    },
    {
      'country': 'Guernsey',
      'countryRU': '????????????',
      'internalPhoneCode': '44',
      'countryCode': 'GG',
      'phoneMask': '+00 (0) 0000 000000',
    },
    {
      'country': 'Hong Kong',
      'countryRU': '??????????????',
      'internalPhoneCode': '852',
      'countryCode': 'HK',
      'phoneMask': '+000 0000 0000',
    },
    {
      'country': 'Iran, Islamic Republic of',
      'countryRU': '????????, ?????????????????? ????????????????????',
      'internalPhoneCode': '98',
      'countryCode': 'IR',
      'phoneMask': '+00 000 000 0000',
    },
    {
      'country': 'Korea, Democratic People\'s Republic of',
      'countryRU': '??????????, ??????????????-?????????????????????????????? ????????????????????',
      'internalPhoneCode': '850',
      'countryCode': 'KP',
      'phoneMask': '+000 0 000 0000',
    },
    {
      'country': 'Korea, Republic of',
      'countryRU': '??????????, ????????????????????',
      'internalPhoneCode': '82',
      'countryCode': 'KR',
      'phoneMask': '+00 0 000 0000',
    },
    {
      'country': '(Laos) Lao People\'s Democratic Republic',
      'countryRU': '(????????) ???????????????? ??????????????-?????????????????????????????? ????????????????????',
      'internalPhoneCode': '856',
      'countryCode': 'LA',
      'phoneMask': '+000 00 0000 0000',
    },
    {
      'country': 'Libyan Arab Jamahiriya',
      'countryRU': '?????????????????? ???????????????? ????????????????????',
      'internalPhoneCode': '218',
      'countryCode': 'LY',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Macao',
      'countryRU': '??????????',
      'internalPhoneCode': '853',
      'countryCode': 'MO',
      'phoneMask': '+000 0000 0000',
    },
    {
      'country': 'Macedonia',
      'countryRU': '??????????????????',
      'internalPhoneCode': '389',
      'countryCode': 'MK',
      'phoneMask': '+000 0 000 0000',
    },
    {
      'country': 'Micronesia, Federated States of',
      'countryRU': '????????????????????, ???????????????????????? ??????????',
      'internalPhoneCode': '691',
      'countryCode': 'FM',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Moldova, Republic of',
      'countryRU': '??????????????, ????????????????????',
      'internalPhoneCode': '373',
      'countryCode': 'MD',
      'phoneMask': '+000 000 00000',
    },
    {
      'country': 'Mozambique',
      'countryRU': '????????????????',
      'internalPhoneCode': '258',
      'countryCode': 'MZ',
      'phoneMask': '+000 000 000000',
    },
    {
      'country': 'Palestina',
      'countryRU': '??????????????????',
      'internalPhoneCode': '970',
      'countryCode': 'PS',
      'phoneMask': '+000 0 000 0000',
    },
    {
      'country': 'Pitcairn',
      'countryRU': '??????????????',
      'internalPhoneCode': '64',
      'countryCode': 'PN',
      'phoneMask': '+00 0 000 0000',
    },
    {
      'country': 'R??union',
      'countryRU': '??????????????',
      'internalPhoneCode': '262',
      'countryCode': 'RE',
      'phoneMask': '+000 000 00 00 00',
    },
    {
      'country': 'Russia',
      'countryRU': '????????????',
      'internalPhoneCode': '7',
      'countryCode': 'RU',
      'phoneMask': '+0 (000) 000-00-00',
    },
    {
      'country': 'Saint Barth??lemy',
      'countryRU': '??????-??????????????????',
      'internalPhoneCode': '590',
      'countryCode': 'BL',
      'phoneMask': '+000 000 00 00 00',
    },
    {
      'country': 'Saint Helena, Ascension and Tristan Da Cunha',
      'countryRU': '???????????? ??????????, ???????????????????? ?? ??????????????-????-??????????',
      'internalPhoneCode': '290',
      'countryCode': 'SH',
      'phoneMask': '+000 0000',
    },
    {
      'country': 'Saint Kitts and Nevis',
      'countryRU': '????????-???????? ?? ??????????',
      'internalPhoneCode': '1869',
      'countryCode': 'KN',
      'phoneMask': '+0 (000) 000 0000',
    },
    {
      'country': 'Saint Lucia',
      'countryRU': '????????-??????????',
      'internalPhoneCode': '1758',
      'countryCode': 'LC',
      'phoneMask': '+0 (000) 000 0000',
    },
    {
      'country': 'Saint Martin',
      'countryRU': '??????-????????????',
      'internalPhoneCode': '590',
      'countryCode': 'MF',
      'phoneMask': '+000 000 000000',
    },
    {
      'country': 'Saint Pierre and Miquelon',
      'countryRU': '??????-???????? ?? ??????????????',
      'internalPhoneCode': '508',
      'countryCode': 'PM',
      'phoneMask': '+508 00 00 00',
    },
    {
      'country': 'Saint Vincent and the Grenadines',
      'countryRU': '????????-?????????????? ?? ??????????????????',
      'internalPhoneCode': '1784',
      'countryCode': 'VC',
      'phoneMask': '+0 (000) 000 0000',
    },
    {
      'country': 'Sao Tome and Principe',
      'countryRU': '????????-?????????????? ?? ??????????????????',
      'internalPhoneCode': '239',
      'countryCode': 'ST',
      'phoneMask': '+000 000 0000',
    },
    {
      'country': 'Somalia',
      'countryRU': '????????????',
      'internalPhoneCode': '252',
      'countryCode': 'SO',
      'phoneMask': '+000 00 000 000',
    },
    {
      'country': 'Svalbard and Jan Mayen',
      'countryRU': '???????????????????? ?? ????-??????????',
      'internalPhoneCode': '47',
      'countryCode': 'SJ',
      'phoneMask': '+00 0000 0000',
    },
    {
      'country': 'Syrian Arab Republic',
      'countryRU': '?????????????????? ???????????????? ????????????????????',
      'internalPhoneCode': '963',
      'countryCode': 'SY',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Taiwan',
      'countryRU': '??????????????',
      'internalPhoneCode': '886',
      'countryCode': 'TW',
      'phoneMask': '+000 0 0000 0000',
    },
    {
      'country': 'Tanzania',
      'countryRU': '????????????????',
      'internalPhoneCode': '255',
      'countryCode': 'TZ',
      'phoneMask': '+000 00 000 0000',
    },
    {
      'country': 'Timor-Leste',
      'countryRU': '??????????-??????????',
      'internalPhoneCode': '670',
      'countryCode': 'TL',
      'phoneMask': '+000 000 000',
    },
    {
      'country': 'Venezuela, Bolivarian Republic of',
      'countryRU': '??????????????????, ???????????????????????????? ????????????????????',
      'internalPhoneCode': '58',
      'countryCode': 'VE',
      'phoneMask': '+00 000 000 0000',
    },
    {
      'country': 'Viet Nam',
      'countryRU': '??????????????',
      'internalPhoneCode': '84',
      'countryCode': 'VN',
      'phoneMask': '+00 000 000 0000',
    },
    {
      'country': 'Virgin Islands, British',
      'countryRU': '???????????????????? ??????????????, ????????????????????',
      'internalPhoneCode': '1284',
      'countryCode': 'VG',
      'phoneMask': '+0 (000) 000 0000',
    },
    {
      'country': 'Virgin Islands, U.S.',
      'countryRU': '???????????????????? ??????????????, ??????',
      'internalPhoneCode': '1340',
      'countryCode': 'VI',
      'phoneMask': '+0 (000) 000 0000',
    }
  ];
}
