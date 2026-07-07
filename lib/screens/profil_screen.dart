import 'package:flutter/material.dart';
import 'package:miloka/screens/login_screen.dart';
import 'package:miloka/service/storage_service.dart';

class ProfilScreen extends StatefulWidget {
  const ProfilScreen({super.key});

  @override
  State<StatefulWidget> createState() {
    // TODO: implement createState
    return _ProfilScreenState();
  }
}

class _ProfilScreenState extends State<ProfilScreen> {
  late String _username = 'Gasy Strem';
  late String _email = 'Gasystrem@gmail.com';

  void loadState() async {
    //var username = await UserStorage.storage.read(key: 'username');
    var email = await UserStorage.readUserStorage();

    setState(() {
      //_username = username ?? _username;
      _email = email ?? _email;
    });
  }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    loadState();
  }

  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    return Scaffold(
      appBar: AppBar(
        title: Text('Profil', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        leading: IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () {
                  Navigator.pop(context);
                },
              )
      ),
      body: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              SizedBox(height: 20),
              Column(
                children: [
                  CircleAvatar(
                    backgroundImage: AssetImage('assets/images/icon.png'),
                    foregroundColor: Colors.black,
                    radius: 50,
                  ),
                  SizedBox(height: 20),
                  //Text(_username, /*style:  AppTextStyles.title */),
                  Text(_email, /* style: AppTextStyles.subtitle */),
                ],
              ),

              Expanded(
                child: ListView(
                  padding: EdgeInsets.all(20),
                  children: [
                    ElevatedButton(
                      style: ButtonStyle(
                        maximumSize: 
                             MaterialStateProperty.all(Size(double.infinity, 40))
                            
                      ),
                      onPressed: () async {
                        /* await NotificationService.notifications
                            .resolvePlatformSpecificImplementation<
                              fln.AndroidFlutterLocalNotificationsPlugin
                            >()
                            ?.requestNotificationsPermission();

                        await NotificationService.notifications.show(
                          id: 0,
                          title: 'Nouveau film',
                          body: 'Un nouveau film est disponible',
                          notificationDetails: const fln.NotificationDetails(
                            android: fln.AndroidNotificationDetails(
                              'film_channel',
                              'Films',
                              channelDescription: 'Notifications des films',
                              importance: fln.Importance.max,
                              priority: fln.Priority.high,
                            ),
                          ),
                        ); */
                      },
                      child: Text('Notification', style: TextStyle(fontSize: 10)),
                    ),
                    SizedBox(height: 5),
                    ElevatedButton(
                      style: ButtonStyle(
                        maximumSize: 
                             MaterialStateProperty.all(Size(double.infinity, 40))
                            
                      ),
                      onPressed: () {
                        /* Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => FavorieScreen()),
                        ); */
                      },
                      child: Text('Mes favoris', style: TextStyle(fontSize: 10)),
                    ),
                    SizedBox(height: 5),
                    ElevatedButton(
                      style: ButtonStyle(
                        maximumSize: 
                             MaterialStateProperty.all(Size(double.infinity, 40))
                            
                      ),
                      onPressed: () {
                        /* Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => SubscriptionScreen()),
                        ); */
                      },
                      child: Text('Abonnement', style: TextStyle(fontSize: 10)),
                    ),
                    SizedBox(height: 5),
                    ElevatedButton(
                      style: ButtonStyle(
                        maximumSize: 
                             MaterialStateProperty.all(Size(double.infinity, 40))
                            
                      ),
                      onPressed: () {}, child: Text('Language', style: TextStyle(fontSize: 10))),
                    SizedBox(height: 5),
                    ElevatedButton(
                      onPressed: () {
                        TokenStorage.deleteTokenStorage();
                        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginScreen()));
                      },
                      style: ButtonStyle(
                        backgroundColor: MaterialStateProperty.all(
                          Colors.black,
                        ),
                      ),
                      child: Text('Déconnexion'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
