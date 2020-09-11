import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:http/http.dart' as http;

void main(List<String> arguments) async {
  var parser = ArgParser()
    ..addOption('wait',
        help: 'Wait time between calls',
        valueHelp: 'seconds',
        abbr: 'w',
        defaultsTo: '0');

  var args = parser.parse(arguments);
  if (args.rest.isEmpty) {
    help(parser);
    return;
  }
  var inputPath = args.rest[0];
  if (inputPath == 'help') {
    help(parser);
    return;
  }
  if (args.rest.length < 2) {
    stderr.write('Specify an output file\n');
    return;
  }
  var outputPath = args.rest[1];

  var input = await File(args.rest[0]).readAsString();
  var asins = LineSplitter().convert(input).where((line) => line.length == 10);
  var failCount = 0;

  var waitDuration = Duration(seconds: int.tryParse(args['wait']) ?? 0);

  var outputFile = File(outputPath);
  await writeAndClose(
      outputFile,
      'ASIN, Title, MFNVariableClosingFee, MFNFixedClosingFee, MFNReferralFee, '
      'AFNStorageFee, AFNVariableCLosingFee, AFNPickAndPackFee, '
      'AFNFixedClosingFee, AFNReferralFee\n');

  for (var asin in asins) {
    try {
      var productResponse = await http.get(
          'https://sellercentral.amazon.co.uk/fba/profitabilitycalculator/productmatches?searchKey=$asin&searchType=keyword&profitcalcToken=testToken');
      var productData = jsonDecode(productResponse.body)['data'][0];
      var title = productData['title'];
      print('$asin, $title');

      var feesResponse = await http.post(
          'https://sellercentral.amazon.co.uk/fba/profitabilitycalculator/getafnfee?profitcalcToken=testToken',
          body: jsonEncode({
            'productInfoMapping': productData,
            'afnPriceStr': 0,
            'mfnPriceStr': 0,
            'mfnShippingPriceStr': 0,
            'currency': 'GBP',
            'marketPlaceId': 'A1F83G8C2ARO7P',
            'hasFutureFee': false,
            'futureFeeDate': '2020-05-01 00:00:00',
            'hasTaxPage': true,
          }));
      var feeData = jsonDecode(feesResponse.body)['data'];
      var mfnFees = feeData['mfnFees'];
      var afnFees = feeData['afnFees'];

      String feeList(String feeType) => feeData[feeType]
          .entries
          .map((entry) => entry.value['amount'])
          .join(', ');

      await writeAndClose(outputFile,
          '$asin, $title, ${feeList('mfnFees')}, ${feeList('afnFees')}\n');
      await Future.delayed(waitDuration);
    } catch (e) {
      stderr.write(e + '\n');
      failCount++;
      print('Fail count: $failCount');
      if (failCount == 5) {
        print('Exiting');
        break;
      }
    }
  }
}

void help(ArgParser parser) {
  print('fba_scraper [input=<path>] [output=<path>]');
  print(parser.usage);
}

Future<void> writeAndClose(File file, String data) async {
  var writeStream = file.openWrite(mode: FileMode.writeOnlyAppend);
  writeStream.write(data);
  await writeStream.close();
}
