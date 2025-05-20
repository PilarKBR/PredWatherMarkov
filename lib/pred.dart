import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
import 'dart:math';
import 'package:intl/intl.dart';

class PrediksiCuacaPage extends StatefulWidget {
  const PrediksiCuacaPage({super.key});

  @override
  State<PrediksiCuacaPage> createState() => _PrediksiCuacaPageState();
}

class _PrediksiItem {
    final String iconPath;
    final DateTime tanggal;
    final String state;
    _PrediksiItem(this.iconPath, this.tanggal, this.state);
  }

class _PrediksiCuacaPageState extends State<PrediksiCuacaPage> {
  final TextEditingController _hariController = TextEditingController();
  final PageController _pageController = PageController();

  String hasilPrediksi = "";
  String tanggalTerakhir = "";
  String hasilPrediksiIconPath = '';
  String hasilPrediksiProbabilitas = '';
  String hasilPrediksiState = '';
  String hasilPrediksiPersen = '';
  String stateTerakhir = '';
  DateTime? tanggalPrediksiDipilih;

  bool isPrediksiSelesai = false;
  List<_PrediksiItem> hasilPrediksiList = [];
  List<String> states = ["Tidak Hujan", "Hujan Ringan", "Hujan Sedang", "Hujan Lebat", "Hujan Sangat Lebat"];
  Map<String, int> stateToIndex = {};
  List<List<double>> probabilitas = [];
  
  final GlobalKey _titleKey = GlobalKey();
  // ignore: prefer_final_fields
  double _toolbarHeight = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateToolbarHeight());
    for (int i = 0; i < states.length; i++) {
      stateToIndex[states[i]] = i;
    }
    bacaDataDanHitungTransisi();
    _pageController.addListener(() {
      if (_pageController.page == 0 && isPrediksiSelesai) {
        ulangiPrediksi();
      }
    });
  }

  void _updateToolbarHeight() {
    final RenderBox? box = _titleKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) {
      setState(() {
        _toolbarHeight = box.size.height;
      });
    }
  }

  List<List<double>> multiplyMatrix(List<List<double>> a, List<List<double>> b) {
    int n = a.length;
    List<List<double>> result = List.generate(n, (_) => List.filled(n, 0.0));
    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        for (int k = 0; k < n; k++) {
          result[i][j] += a[i][k] * b[k][j];
        }
      }
    }
    return result;
  }

  List<List<double>> matrixPower(List<List<double>> matrix, int power) {
    int n = matrix.length;
    List<List<double>> result = List.generate(n, (i) => List.generate(n, (j) => i == j ? 1.0 : 0.0)); 
    List<List<double>> base = matrix.map((row) => [...row]).toList(); 

    while (power > 0) {
      if (power % 2 == 1) {
        result = multiplyMatrix(result, base);
      }
      base = multiplyMatrix(base, base);
      power ~/= 2;
    }
    return result;
  }

  Future<void> bacaDataDanHitungTransisi() async {
    final csvRaw = await rootBundle.loadString('assets/cuaca.csv');
    final rows = LineSplitter().convert(csvRaw).skip(1);

    final lastLine = csvRaw.trim().split('\n').last.split(',');
    double lastRR = 0;
    if (lastLine.length >= 2) {
      lastRR = double.tryParse(lastLine[1]) ?? 0;
      stateTerakhir = intensitasKeState(lastRR);
    }

    List<String> kategoriList = [];
    for (var row in rows) {
      final parts = row.split(',');
      if (parts.length >= 2) {
        kategoriList.add(intensitasKeState(double.tryParse(parts[1]) ?? 0));
      }
    }

    final n = states.length;
    List<List<double>> transisi = List.generate(n, (_) => List.filled(n, 0));

    for (int i = 0; i < kategoriList.length - 1; i++) {
      int a = stateToIndex[kategoriList[i]]!;
      int b = stateToIndex[kategoriList[i + 1]]!;
      transisi[a][b] += 1;
    }

    probabilitas = List.generate(n, (i) {
      final total = transisi[i].reduce((a, b) => a + b);
      return total == 0 ? List.filled(n, 0) : transisi[i].map((v) => v / total).toList();
    });

    if (lastLine.isNotEmpty) {
      tanggalTerakhir = lastLine[0]; 
    }
    setState(() {});
  }

  String intensitasKeState(double mm) {
    if (mm == 0) return "Tidak Hujan";
    if (mm < 20) return "Hujan Ringan";
    if (mm < 50) return "Hujan Sedang";
    if (mm < 100) return "Hujan Lebat";
    return "Hujan Sangat Lebat";
  }

  List<_PrediksiItem> prediksiCuacaChapmanKolmogorov(String stateAwal, int nHari) {
    int idxAwal = stateToIndex[stateAwal]!;
    List<double> distribusi;

    List<List<double>> transisiN = matrixPower(probabilitas, nHari);
    distribusi = transisiN[idxAwal]; 

    int idxPrediksi = 0;
    double maxProb = distribusi[0];
    for (int i = 1; i < distribusi.length; i++) {
      if (distribusi[i] > maxProb) {
        maxProb = distribusi[i];
        idxPrediksi = i;
      }
    }

    DateTime startDate;
    try {
      startDate = DateTime.parse(tanggalTerakhir);
    } catch (_) {
      startDate = DateTime.now();
    }

    final tanggalPrediksi = startDate.add(Duration(days: nHari));
    final prediksiState = states[idxPrediksi];
    final prediksiPersen = (maxProb * 100).toStringAsFixed(2);
    final prediksiIkon = 'assets/${stateToFilename(prediksiState)}.png';

    // ignore: unnecessary_string_interpolations
    hasilPrediksiState = "$prediksiState";
    hasilPrediksiPersen = "$prediksiPersen%";
    hasilPrediksiIconPath = prediksiIkon;

    List<_PrediksiItem> hasilDistribusi = [];
    for (int i = 0; i < distribusi.length; i++) {
      String persen = (distribusi[i] * 100).toStringAsFixed(2);
      hasilDistribusi.add(
        _PrediksiItem('assets/${stateToFilename(states[i])}.png', tanggalPrediksi, "${states[i]} ($persen%)")
      );
    }
    return hasilDistribusi;
  }


  String stateToFilename(String state) {
    return state.toLowerCase().replaceAll(' ', '_'); 
  }

  int pilihBerdasarkanProbabilitas(List<double> probs, Random rand) {
    double r = rand.nextDouble();
    double cumulative = 0.0;
    for (int i = 0; i < probs.length; i++) {
      cumulative += probs[i];
      if (r <= cumulative) return i;
    }
    return probs.length - 1;
  }

  void handlePrediksi() {
    if (tanggalPrediksiDipilih == null || tanggalTerakhir.isEmpty) {
      setState(() {
        hasilPrediksiList = [];
        hasilPrediksi = "";
        isPrediksiSelesai = true;
      });
      return;
    }

    DateTime tanggalTerakhirDateTime = DateFormat('dd-MM-yyyy').parse(tanggalTerakhir);
    int nHari = tanggalPrediksiDipilih!.difference(tanggalTerakhirDateTime).inDays;

    if (nHari < 0 || probabilitas.isEmpty || stateTerakhir.isEmpty || !stateToIndex.containsKey(stateTerakhir)) {
      setState(() {
        hasilPrediksiList = [];
        hasilPrediksi = "";
        isPrediksiSelesai = true;
      });
      return;
    } else {
      final prediksi = prediksiCuacaChapmanKolmogorov(stateTerakhir, nHari);
      setState(() {
        hasilPrediksiList = prediksi;
        isPrediksiSelesai = true;
      });
    }

    Future.delayed(const Duration(milliseconds: 300), () {
      _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  void ulangiPrediksi() {
    setState(() {
      isPrediksiSelesai = false;
      hasilPrediksi = "";
      _hariController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;
    final formattedDate = tanggalPrediksiDipilih != null
      ? DateFormat("d MMMM yyyy", "id_ID").format(tanggalPrediksiDipilih!)
      : "";

    return Scaffold(
      body: PageView(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        physics: const PageScrollPhysics(),
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/rainy.png'),
                  const Text("Prediktor Curah Hujan", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                  SizedBox(height: screenHeight * 0.02),
                  const Text("Masukkan jumlah hari yang akan diprediksi:", style: TextStyle(fontSize: 16, color: Colors.white)),
                  SizedBox(height: screenHeight * 0.00616),
                  ElevatedButton(
                    onPressed: () async {
                      DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );

                      if (picked != null && tanggalTerakhir.isNotEmpty) {
                        DateTime lastDate = DateTime.tryParse(tanggalTerakhir) ?? DateTime.now();
                        int selisihHari = picked.difference(lastDate).inDays;
                        if (selisihHari >= 0) {
                          setState(() {
                            tanggalPrediksiDipilih = picked;
                          });
                          _hariController.text = selisihHari.toString();
                          handlePrediksi();
                        } else {
                          // ignore: use_build_context_synchronously
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Pilih tanggal setelah data terakhir.")),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: const Text("Pilih Tanggal Prediksi"),
                  ),
                  SizedBox(height: screenHeight * 0.0164271),
                  Text("Data terakhir yang dihimpun: $tanggalTerakhir", style: const TextStyle(fontSize: 14, color: Colors.white)),
                ],
              ),
            ),
          ),
          Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.lightBlue,
              toolbarHeight: _toolbarHeight > 0 ? _toolbarHeight : screenHeight * 0.325,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
              ),
              centerTitle: true,
              title: Column(
                key: _titleKey,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  isPrediksiSelesai 
                    ? Column(
                      children: [
                        Text(
                          "Pada tanggal $formattedDate diprediksi akan terjadi",
                          style: const TextStyle(fontSize: 15, color: Colors.white),
                        ),
                        SizedBox(height: screenHeight * 0.00616),
                        Text(
                          hasilPrediksiState,
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold,),
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: screenHeight * 0.00616),
                        Image.asset(
                          hasilPrediksiIconPath,
                          width: screenWidth * 0.25,
                        ),
                        SizedBox(height: screenHeight * 0.00616),
                        Text(
                          "Dengan Persentase sebesar",
                          style: TextStyle(fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: screenHeight * 0.00616),
                        Text(
                          hasilPrediksiPersen,
                          style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold,),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    )
                    : const Text("Tanggal belum dipilih", style: TextStyle(fontSize: 15, color: Colors.white),),
                  SizedBox(height: screenHeight * 0.00616),
                  Icon(Icons.keyboard_arrow_down, size: screenHeight * 0.035, color: Colors.white),
                ],
              ),
            ),
            body: SafeArea(
              minimum: EdgeInsets.fromLTRB(screenWidth * 0.04, 0, screenWidth * 0.04, 0),
              child: Column(
                children: [
                  Expanded(
                    child: Column(
                        children: [
                          Table(
                            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                            columnWidths: {
                              0: FlexColumnWidth(),
                              1: FlexColumnWidth(),
                            },
                            children: [
                              for (final item in hasilPrediksiList)
                                TableRow(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Image.asset(
                                            item.iconPath,
                                            height: screenHeight * 0.035,
                                            width: screenWidth * 0.075,
                                          ),
                                          SizedBox(width: screenWidth * 0.02),
                                          Text(
                                            item.state.split('(')[0].trim(),
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(
                                        item.state.contains('(')
                                            ? item.state.split('(')[1].replaceAll(')', '')
                                            : "-",
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          SizedBox(height: screenHeight * 0.02),
                        ],
                      ),
                    ),
                ]
              )
            ),
          ),
        ],
      ),
    );
  }
}
