/*

сохр локально в локалсторадж

сохр в файрстори, как в эксп. системах. для обмена

share result
as png

 */

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/rendering.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'ChooseTaleToRestore.dart';
import 'globals.dart';
import 'taleLib.dart';
import 'About.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'EditWordOptions.dart';
import 'EnterTaleName.dart';
import 'ChooseNewOrExist.dart';
import 'package:share_extend/share_extend.dart';
import 'dart:ui' as ui;

enum TtsState { playing, stopped, paused, continued }
Color taleBG = Colors.tealAccent[100]!;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initHive();
  runApp(MyApp());
}

List <String> splitWordAndPunctuation(String sourceWord){
  String word = sourceWord;
  String lastChar = word.length < 2? '' : word[word.length-1];
  if (lastChar != '') {
    if ('.,!:#%^&*();-+?<>/\'\"\$'.indexOf(lastChar) > -1) {
      word = word.substring(0, word.length-1);
    } else {
      lastChar = '';
    }
  }
  return [word, lastChar];
}

List <String> findOpt2(var opt2, String s) {
  List<String> res = [];
  opt2.forEach((lOpts) {
    bool isInList = false;
    lOpts.forEach((el){
      if (s.toUpperCase()==el.toUpperCase()){
        isInList = true;
      }
    });
    if (isInList) {
      lOpts.forEach((element){
        if (res.indexOf(element)==-1)
          res.add(element);
      });
    }
  });
  return res;
}

initHive() async {
  print('init hive');
  if (kIsWeb) {
    await Hive.initFlutter();
  } else {
    final appDocDir = await path_provider.getApplicationDocumentsDirectory();
    print('got path ${appDocDir.path}');
    await Hive.initFlutter(appDocDir.path);
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Придумай сказку!',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: SelectTale(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key}) : super(key: key);
  final String title = 'Придумай сказку!';

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<String> myTale = [];
  String myTaleName = '', myNickName = '';
  var myOptions;
  List<String> selectedOptions = [];
  String baseTale = 'kurRyaba';

  bool isWordSelected = false;
  bool isStartMsg = true;

  int curL=0, curW=0;
  bool stopTale = false, playMode = false;
  String myTaleBGpic='';
  var hiveVarBox;
  bool startMode = true, zeroStartMode = true;

  FlutterTts flutterTts = FlutterTts();
  dynamic languages;
  String language='Ru-ru';
  double volume = 1;
  double pitch = 1.4;
  double rate = 1;

  TtsState ttsState = TtsState.stopped;
  get isPlaying => ttsState == TtsState.playing;
  get isStopped => ttsState == TtsState.stopped;
  get isPaused => ttsState == TtsState.paused;
  get isContinued => ttsState == TtsState.continued;

  final _scrollController1 = ScrollController();
  double opacityLvl = 1.0;
  var hiveSaveBox;

  GlobalKey _globalKey = GlobalKey();

  @override
  void initState() {
    baseTale = glBaseTale;
    //Box<dynamic> nickNameBox = Hive.openBox('nickName').then((value) {
    try {
      Hive.openBox('nickName').then((nickNameBox) {
        myNickName = nickNameBox.get('nick') ?? '';
        print('got saved nickname $myNickName');
      });
    } catch(e) {

    }
    myTale = getTale(baseTale);
    myOptions = getOptions(baseTale);
    myTaleBGpic = getBGpicFileName(baseTale);

    prepareWordOptionsAndRandomizeAnimation();

    selectedOptions = [];
    selectedOptions.add(
        'Нажми на слово, которое ты хочешь изменить. \n'
        'Потом в нижнем окне выбери (или добавь) замену. \n'
        'И послушай, что получилось!\n'
        'Перешли другу и посмейтесь вместе)');
    initTts();
    super.initState();
  }

  prepareWordOptionsAndRandomizeAnimation() async {
    hiveVarBox = await Hive.openBox('MyOptions');

    if (hiveVarBox.length == 0) {
      hiveVarBox.put(baseTale, jsonEncode(myOptions));
    } else {
      String myOptEncoded = hiveVarBox.get(baseTale) ?? '';
      if (myOptEncoded == null || myOptEncoded.length == 0) {
        hiveVarBox.put(baseTale, jsonEncode(myOptions));
      } else {
        myOptions = jsonDecode(myOptEncoded);
      }
    }

    await delay(2000);

    setState(() {
      opacityLvl = 0;
      print('opac 0');
    });

    await delay(2000);

    randomizeMyTale();

    setState(() {
      zeroStartMode = false;
      opacityLvl = 1;
      print('opac 1');
    });
  }

  Future<void> _speak(String _text) async {
    print('speak $_text');
    await flutterTts.speak(_text);
  }

  Future<void> delay(int dur) {
    final c = new Completer();
    Future.delayed(Duration(milliseconds: dur), () {
      c.complete("ok");
    });
    return c.future;
  }

  initTts() async {
    flutterTts = FlutterTts();
    await flutterTts.awaitSpeakCompletion(true);
    await flutterTts.setVolume(volume);
    await flutterTts.setSpeechRate(0.42);
    await flutterTts.setPitch(1);
    // ru-RU uk-UA en-US
    await flutterTts.setLanguage('ru-RU');
  }

  void randomizeMyTale() {
    for (int i=0; i<myTale.length; i++) {
      List <String> lineWords = myTale[i].split(' ');
      for (int j=0; j < lineWords.length; j++) {
        List <String> lwp = splitWordAndPunctuation(lineWords[j]);
        String sourceWord = lwp[0];
        String lastChar = lwp[1];
        List <String> lOptions = findOpt2(myOptions, sourceWord);
        if (lOptions.length == 0) {
          continue;
        }
        lineWords[j] = chooseNewRandomWord(lOptions) + lastChar;
      }
      myTale[i] = lineWords.join(' ');
    }
  }

  @override
  void dispose() {
    super.dispose();
    flutterTts.stop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(child: Text(widget.title)),
            IconButton(
                icon: Icon(Icons.import_contacts, size: 30,),
                onPressed: _changeBaseTale,
            ),
          ],
        ),
      ),
      body: RepaintBoundary(
        key: _globalKey,
        child: Container(
          decoration: new BoxDecoration(
            image: new DecorationImage(
              image: new AssetImage('images/'+myTaleBGpic),
              fit: BoxFit.cover,
            ),
          ),
          padding: const EdgeInsets.all(10.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                flex: 2,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: opacityLvl,
                    duration: Duration(seconds: 2),
                    child: Container(
                      child: Scrollbar(
                        controller: _scrollController1, // <---- Here, the controller
                        isAlwaysShown: true,
                        child: ListView(
                          shrinkWrap: true,
                          controller: _scrollController1,
                          children: taleWList(),
                        ),
                      ),
                    ),
                  ),
                )
              ),
              zeroStartMode? SizedBox() :
                Expanded(
                  flex: 1,
                  child: Stack(
                    children: [
                      Container(
                        height: double.infinity,
                        width: MediaQuery.of(context).size.width * 0.8,
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.lightBlueAccent.withOpacity(0.5),
                        ),
                        child: SingleChildScrollView(
                          child: Container(
                            margin: EdgeInsets.only(top: 32),
                            child: playMode?
                            SizedBox(height:10)
                            : Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              runAlignment: WrapAlignment.center,
                              spacing: 10,
                              runSpacing: 10,
                              children: addonsWList(),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: -16,
                        width: 120, height: 35,
                        child: startMode? SizedBox(height: 10) :
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FloatingActionButton(onPressed: _editWordOptions, child: Icon(Icons.edit, size: 25,), heroTag: "btnEdit",),
                              FloatingActionButton(
                                backgroundColor: Colors.deepOrange,
                                onPressed: (){
                                  zeroStartMode = true;
                                  setState(() {});
                                },
                                child: Icon(Icons.close, size: 25,), heroTag: "btnClose",),
                            ],
                          )
                      )
                    ],
                  ),
              )
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        color: Colors.brown[300],
          height: 50,
          child: ButtonBar(
          alignment: MainAxisAlignment.spaceAround,
          buttonPadding: EdgeInsets.all(3),
          children: [
            FloatingActionButton(onPressed: _showAbout, tooltip: 'О программе', child: Text('?', textScaleFactor: 2,), heroTag: "btnAbout",),
            FloatingActionButton(onPressed: _shuffleWords, tooltip: 'Новая сказка', child: Icon(Icons.shuffle, size: 30,), heroTag: "btnShuffle"),
            playMode? FloatingActionButton(onPressed: _stopTaleReading, child: Icon(Icons.stop, size: 30,), heroTag: "btnStop") : FloatingActionButton(onPressed: _soundCurTale, child: Icon(Icons.play_arrow, size: 30,), heroTag: "btnSpeak"),
            FloatingActionButton(onPressed: _saveCurTale, tooltip: 'Сохранить сказку', child: Icon(Icons.save, size: 30,), heroTag: "btnSaveTale"),
            FloatingActionButton(onPressed: _restoreCurTale, tooltip: 'Открыть сказку', child: Icon(Icons.open_in_browser, size: 30,), heroTag: "btnRestoreTale"),
            FloatingActionButton(onPressed: _shareTale, child: Icon(Icons.share, size: 30,), heroTag: "btnShare"),
            // FloatingActionButton(onPressed: _exchTales, tooltip: 'Обмен сказками', child: Icon(Icons.language, size: 30,), heroTag: "btnExch"),
          ],
      )),
    );
  }

  void _soundCurTale() async {
    setState(() {
      playMode = true;
    });
    for (int i=0; i < myTale.length; i++) {
      await _speak(myTale[i]);
      await delay(100);
      if (stopTale) {
        stopTale = false;
        break;
      }
    }
    setState(() {
      playMode = false;
    });
  }

  List<Widget> addonsWList() {
    List <Widget> addonsWL = [];
    selectedOptions.forEach((element) {
      addonsWL.add(
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: InkWell(
              splashColor: Colors.yellow,
              highlightColor: Colors.blue.withOpacity(0.5),
              child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.white,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 5.0, right: 5),
                    child: Text(element, textScaleFactor: 1.3, textAlign: TextAlign.center,),
                  )
              ),
                onTap: () {
                  setState(() {
                    replaceCurWordOfTale(element);
                  });
                },
            ),
          )
      );
    });
    //addonsWL.shuffle();
    return addonsWL;
  }

  List<Widget> taleWList() {
    List<Widget> twl = [];
    for (int i=0; i < myTale.length; i++) {
      List<String> wordsL = myTale[i].trim().split(' ');
      List<Widget> wordsWL = [];
      for (int j=0; j < wordsL.length; j++) {
        wordsWL.add(
            InkWell(
              splashColor: Colors.yellow,
              highlightColor: Colors.blue.withOpacity(0.5),
              onTap: () {
                curL = i; curW = j; startMode = false;
                zeroStartMode = false;
                setState(() {
                  findOptions(i, j);
                });
              },
              child: Container(
                  margin: EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: ((i==curL && j==curW)? Colors.teal[200]: taleBG),
                  ),
                  //color: ((i==curL && j==curW)? Colors.teal[200]: taleBG),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 5),
                    child: Text(wordsL[j]+' ', textScaleFactor: 1.25,),
                  )
              ),
            )
        );
      }
      twl.add(
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Wrap(
            alignment: WrapAlignment.center,
            children: wordsWL,
          ),
        )
      );
    }
    return twl;
  }

  List<String> getConcreteOptions(int i, int j) {
    List <String> lWordsOfCurRow = myTale[i].split(' ');
    String word = splitWordAndPunctuation(lWordsOfCurRow[j])[0];
    return findOpt2(myOptions, word);
  }

  String chooseNewRandomWord(List<String> lVariants) {
    var rng = new Random();
    return lVariants[rng.nextInt(lVariants.length)];
  }

  void findOptions(int i, int j) {
    selectedOptions = getConcreteOptions(i, j);
  }

  void replaceCurWordOfTale(String newWord) {
    String curS = myTale[curL];
    List <String> words = curS.split(' ');
    words[curW] = newWord + splitWordAndPunctuation(words[curW])[1];
    myTale[curL] = words.join(' ');
  }

  showAlertPage(String msg) {
    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            content: Text(msg),
          );
        }
    );
  }

  _shuffleWords(){
    randomizeMyTale();
    setState(() {
      curL=-1; curW=-1;
    });
  }

  _stopTaleReading(){
    stopTale = true;
    flutterTts.stop();
  }

  _showAbout(){
    Navigator.push(context, MaterialPageRoute(builder: (context) => new About()),);
  }

  void _saveCurTale() async {
    if (myTaleName == '') {
      Navigator.push(context, MaterialPageRoute(builder: (context) => EnterTaleName()),)
      .then((taleName) {
        if (taleName == null) {
          return;
        }
        if (taleName!='') {
          myTaleName = taleName;
          print('new myTaleName $myTaleName');
        }
        saveMyTaleToHiveBox(taleName);
      });
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (context) => ChooseNewOrExist(myTaleName)),)
      .then((choice) {
        if (choice != null) {
          if (choice == 'exist') {
            saveMyTaleToHiveBox(myTaleName);
          } else if (choice == 'new') {
            Navigator.push(context, MaterialPageRoute(builder: (context) => EnterTaleName()),)
                .then((taleName) {
              if (taleName!='') {
                myTaleName = taleName;
                print('new myTaleName $myTaleName');
              }
              saveMyTaleToHiveBox(taleName);
            });
          }
        }
      });
      
    }
  }

  saveMyTaleToHiveBox(String taleName) async {
    if (taleName.toString().trimLeft() == '') {
      showAlertPage('Не сохранил.');
      return;
    }
    var taleBox = await Hive.openBox('tales');
    List <String> newTale = []; newTale.addAll(myTale);

    List<int> cCodes = taleName.codeUnits;
    String encodedName = jsonEncode(cCodes);
    print('encodedName $encodedName');

    taleBox.put(encodedName, newTale);
    showAlertPage('Сохранил $taleName!');
  }

  void _restoreCurTale() async {
    Navigator.push(context, MaterialPageRoute(builder: (context) => ChooseTaleToRestore()),)
        .then((taleName) async {
      print('got taleName to read $taleName');
      if (taleName == null) {
        return;
      }
      if (taleName!='') {
        myTaleName = taleName;
        Box<dynamic> taleBox = await Hive.openBox('tales');
        List<int> cCodes = taleName.codeUnits;
        String encodedName = jsonEncode(cCodes);
        print('encodedName $encodedName');
        var taleL = taleBox.get(encodedName);
        myTale = [];
        setState(() {
          for (int i=0; i < taleL.length; i++) {
            myTale.add(taleL[i]);
          }
        });
      }
    });
  }

  _editWordOptions() async {
    List <String> lineWords = myTale[curL].split(' ');
    String sourceWord = splitWordAndPunctuation(lineWords[curW])[0];
    Navigator.push(context, MaterialPageRoute(builder: (context) => EditWordOptions(sourceWord, myOptions)),)
    .then((value) {
      print('got myOptions');
      print(myOptions);
      hiveVarBox.put(baseTale, jsonEncode(myOptions));
      selectedOptions = getConcreteOptions(curL, curW);
      setState((){});
    });
  }

  void _changeBaseTale() {
    print('_changeBaseTale');
    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('Доступны сказки', textAlign: TextAlign.center,),
            scrollable: true,
            content: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  ElevatedButton(
                    child: Text('Курочка ряба', textScaleFactor: 1.4, style: TextStyle(color: Colors.blue[900]),),
                    onPressed: (){
                      if (baseTale != 'kurRyaba') {
                        baseTale = 'kurRyaba';
                        onChangeBaseTale();
                        Navigator.pop(context);
                      }
                    },
                  ),
                  ElevatedButton(
                    child: Text('Где обедал воробей', textScaleFactor: 1.4, style: TextStyle(color: Colors.blue[900])),
                    onPressed: (){
                      if (baseTale != 'vorobey') {
                        baseTale = 'vorobey';
                        onChangeBaseTale();
                        Navigator.pop(context);
                      }
                    },
                  ),
                  ElevatedButton(
                    child: Text('Мишка', textScaleFactor: 1.4, style: TextStyle(color: Colors.blue[900])),
                    onPressed: (){
                      if (baseTale != 'mishka') {
                        baseTale = 'mishka';
                        onChangeBaseTale();
                        Navigator.pop(context);
                      }
                    },
                  ),
                  ElevatedButton(
                    child: Text('Танечка', textScaleFactor: 1.4, style: TextStyle(color: Colors.blue[900])),
                    onPressed: (){
                      if (baseTale != 'tanya') {
                        baseTale = 'tanya';
                        onChangeBaseTale();
                        Navigator.pop(context);
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        }
    );
  }

  onChangeBaseTale(){
    myTale = getTale(baseTale);
    myOptions = getOptions(baseTale);
    myTaleBGpic = getBGpicFileName(baseTale);
    prepareWordOptionsAndRandomizeAnimation();
    selectedOptions = [];
    setState(() {});
  }

  Future<String> _writeByteToImageFile(ByteData byteData) async {
    Directory? dir = await getApplicationDocumentsDirectory();
//    Platform.isAndroid ? await getExternalStorageDirectory() : await getApplicationDocumentsDirectory();
    File imageFile = File("${dir!.path}/talemaker/${DateTime.now().millisecondsSinceEpoch}.png");
    imageFile.createSync(recursive: true);
    imageFile.writeAsBytesSync(byteData.buffer.asUint8List(0));
    return imageFile.path;
  }

  void _shareTale() async {
    zeroStartMode = true;
    setState(() {});
    await Future.delayed(Duration(milliseconds: 100));
    RenderRepaintBoundary boundary = _globalKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    ui.Image image = await boundary.toImage();
    ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    String fileName = await _writeByteToImageFile(byteData!);
    ShareExtend.shareMultiple([fileName], "image", subject: "Приятного аппетита!");
  }
}

class SelectTale extends StatelessWidget {
  const SelectTale({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    double _tScale = 1.8;
    return Scaffold(
      appBar: AppBar(title: Text('Выбери сказку'),),
      body: DefaultTextStyle(
        style: TextStyle(
          fontSize: 22,
          color: Colors.black
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('В телефоне поселился вирус.', textAlign: TextAlign.center,),
              Text('Который иногда ломает сказки.', textAlign: TextAlign.center),
              Text('Попробуй починить их!', textAlign: TextAlign.center),
              Text('Или придумай новую...', textAlign: TextAlign.center),
              SizedBox(height: 30,),
              Text('Выбери сказку и пробуй!', textAlign: TextAlign.center),
              SizedBox(height: 16,),
              ElevatedButton(
                child: Text('Курочка ряба',
                  textScaleFactor: _tScale,
                ),
                onPressed: (){
                  glBaseTale = 'kurRyaba';
                  Navigator.push(context, MaterialPageRoute(builder: (context) => MyHomePage()),);
                },
              ),
              ElevatedButton(
                child: Text('Где обедал воробей', textScaleFactor: _tScale),
                onPressed: (){
                  glBaseTale = 'vorobey';
                  Navigator.push(context, MaterialPageRoute(builder: (context) => MyHomePage()),);
                },
              ),
              ElevatedButton(
                child: Text('Мишка', textScaleFactor: _tScale),
                onPressed: (){
                  glBaseTale = 'mishka';
                  Navigator.push(context, MaterialPageRoute(builder: (context) => MyHomePage()),);
                },
              ),
              ElevatedButton(
                child: Text('Танечка', textScaleFactor: _tScale),
                onPressed: (){
                  glBaseTale = 'tanya';
                  Navigator.push(context, MaterialPageRoute(builder: (context) => MyHomePage()),);
                },
              ),
              SizedBox(height: 10,),
              Image.asset('images/virus.png'),
            ],
          ),
        ),
      ),
    );
  }
}
