package app.eluno.mobile;

import android.app.*;
import android.os.*;
import android.content.*;
import android.content.res.Configuration;
import android.database.Cursor;
import android.graphics.*;
import android.net.Uri;
import android.net.nsd.*;
import android.net.wifi.WifiManager;
import android.provider.OpenableColumns;
import android.view.*;
import android.widget.*;
import android.text.*;
import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory;
import androidx.media3.datasource.okhttp.OkHttpDataSource;
import androidx.media3.ui.PlayerView;
import com.google.zxing.integration.android.IntentIntegrator;
import com.google.zxing.integration.android.IntentResult;
import org.json.*;
import okhttp3.Response;
import java.io.*;
import java.nio.ByteBuffer;
import java.util.*;
import java.util.concurrent.*;

@UnstableApi
public class MainActivity extends Activity {
    private final ExecutorService jobs = Executors.newFixedThreadPool(4);
    private final ExecutorService polling = Executors.newSingleThreadExecutor();
    private final Map<String,Uri> sources = new ConcurrentHashMap<>();
    private final Map<String,File> sourceCopies = new ConcurrentHashMap<>();
    private volatile boolean preparationCancelled;
    private final Set<String> reading = ConcurrentHashMap.newKeySet();
    private final Set<String> nearby = new LinkedHashSet<>();
    private volatile ElunoApi api;
    private volatile boolean foreground, destroyed;
    private volatile int connectionGeneration;
    private int viewGeneration;
    private final android.util.LruCache<String,Bitmap> thumbnails = new android.util.LruCache<>(24);
    private JSONObject room, incomingTransfer;
    private Transfers transfers;
    private LinearLayout transferList;
    private final Map<String,Long> playbackPositions = new HashMap<>();
    private LinearLayout content, actions, files;
    private TextView status, nearbyText;
    private EditText deviceName, search, collectionName;
    private final Set<String> favorites = new HashSet<>();
    private final List<Uri> externalItems = new ArrayList<>();
    private CheckBox allowCopies, favoritesOnly;
    private String rendered = "", pendingDownload, downloadName, viewedId;
    private Dialog viewer;
    private ExoPlayer player;
    private NsdManager nsd;
    private NsdManager.DiscoveryListener discovery;
    private WifiManager.MulticastLock multicast;

    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        File[] abandoned=getCacheDir().listFiles((directory,name)->name.startsWith("eluno-source-")||name.startsWith("eluno-copy-")||name.startsWith("eluno-photo-"));if(abandoned!=null)for(File file:abandoned)file.delete();
        getWindow().setStatusBarColor(Color.rgb(245,244,236));
        ScrollView scroll = new ScrollView(this);
        content = new LinearLayout(this); content.setOrientation(LinearLayout.VERTICAL); content.setPadding(dp(24),dp(30),dp(24),dp(24)); content.setBackgroundColor(Color.rgb(245,244,236));
        scroll.addView(content); setContentView(scroll);
        text(content,"eluno.",36,true); text(content,"Your world, connected.",22,true);
        status = text(content,"Open Eluno on your computer, then scan its invitation.",15,false);
        deviceName = new EditText(this); deviceName.setSingleLine(); deviceName.setHint("This device’s name"); deviceName.setText(getPreferences(0).getString("name","My Android")); deviceName.setContentDescription("Device name"); content.addView(deviceName);
        actions = vertical(content); button(actions,"Scan computer invitation",this::scan);rememberedActions();
        nearbyText = text(content,"Looking for nearby Eluno computers…",13,false);
        search = new EditText(this); search.setSingleLine(); search.setHint("Search files, collections or devices"); search.setContentDescription("Search shared media"); content.addView(search); search.setVisibility(View.GONE);
        search.addTextChangedListener(new TextWatcher(){ public void beforeTextChanged(CharSequence s,int a,int c,int f){} public void onTextChanged(CharSequence s,int a,int b,int c){renderFiles();} public void afterTextChanged(Editable e){} });
        allowCopies = new CheckBox(this); allowCopies.setText("Allow saving copies of files I add"); allowCopies.setVisibility(View.GONE); content.addView(allowCopies);
        favoritesOnly=new CheckBox(this);favoritesOnly.setText("Favorites in this connection");favoritesOnly.setVisibility(View.GONE);favoritesOnly.setOnCheckedChangeListener((button,checked)->renderFiles());content.addView(favoritesOnly);
        collectionName=new EditText(this);collectionName.setHint("Collection / album name (optional)");collectionName.setContentDescription("Collection or album name for new files");collectionName.setVisibility(View.GONE);if(favoritesOnly!=null)favoritesOnly.setVisibility(View.GONE);content.addView(collectionName);
        files = vertical(content);
        transfers = new Transfers(this); transferList = vertical(content);
        button(content,"Release downloads and updates",()->startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse("https://github.com/beingaeditor/Eluno/releases"))));
        text(content,"Only files you select are shared. Keep Eluno open while sharing.",13,false);
        nsd = (NsdManager)getSystemService(NSD_SERVICE);
        handleIntent(getIntent());
    }
    private int dp(int value){return Math.round(value*getResources().getDisplayMetrics().density);}
    private LinearLayout vertical(LinearLayout parent){LinearLayout box=new LinearLayout(this);box.setOrientation(LinearLayout.VERTICAL);parent.addView(box,new LinearLayout.LayoutParams(-1,-2));return box;}
    private TextView text(LinearLayout parent,String value,int size,boolean bold){TextView label=new TextView(this);label.setText(value);label.setTextSize(size);label.setTextColor(Color.rgb(32,60,50));label.setPadding(0,dp(8),0,dp(8));if(bold)label.setTypeface(null,Typeface.BOLD);parent.addView(label);return label;}
    private void button(LinearLayout parent,String label,Runnable action){Button button=new Button(this);button.setText(label);button.setAllCaps(false);button.setMinHeight(dp(48));button.setTextColor(Color.rgb(23,98,76));parent.addView(button,new LinearLayout.LayoutParams(-1,-2));button.setOnClickListener(v->action.run());}
    private void message(String value){runOnUiThread(()->{if(!destroyed)status.setText(value);});}
    private void work(Task task){jobs.submit(()->{try{task.run();}catch(Exception error){message(error.getMessage()==null?"Something interrupted this action. Try again.":error.getMessage());}});}
    private interface Task {void run() throws Exception;}
    private void scan(){new IntentIntegrator(this).setDesiredBarcodeFormats(IntentIntegrator.QR_CODE).setPrompt("Scan the invitation shown in Eluno on your computer").setBeepEnabled(false).setOrientationLocked(false).initiateScan();}
    @Override protected void onNewIntent(Intent intent){super.onNewIntent(intent);setIntent(intent);handleIntent(intent);}
    private void handleIntent(Intent intent){
        if(intent==null)return;
        if(Intent.ACTION_SEND.equals(intent.getAction())||Intent.ACTION_SEND_MULTIPLE.equals(intent.getAction())){
            externalItems.clear();
            if(Intent.ACTION_SEND.equals(intent.getAction())){Uri uri=intent.getParcelableExtra(Intent.EXTRA_STREAM);if(uri!=null&&"content".equals(uri.getScheme()))externalItems.add(uri);}
            else {ArrayList<Uri> uris=intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM);if(uris!=null)for(Uri uri:uris)if(uri!=null&&"content".equals(uri.getScheme())&&externalItems.size()<50)externalItems.add(uri);}
            externalActions();message("Selected content is ready to review. Connect first, then choose Review files from another app.");
        }else if(intent.getData()!=null)invitation(intent.getData().toString());
    }
    private void externalActions(){if(!externalItems.isEmpty())button(actions,"Review files from another app",()->{if(room==null){message("Connect your devices first.");return;}confirmSelection(new ArrayList<>(externalItems));externalItems.clear();});}
    private void confirmSelection(List<Uri> selected){
        boolean copies=allowCopies.isChecked();String collection=collectionName.getText().toString().trim();
        new AlertDialog.Builder(this).setTitle("Share selected files?").setMessage(selected.size()+" selected items will be listed for your connected devices. Media can be viewed; other files can be sent as approved copies.").setNegativeButton("Cancel",null).setPositiveButton("Share selected files",(dialog,which)->{preparationCancelled=false;work(()->add(selected,copies,collection));}).show();
    }
    private void invitation(String value){
        try {
            if(value.length()>6000)throw new IllegalArgumentException("Invitation is too large.");
            Uri uri=Uri.parse(value);
            if(!"eluno".equals(uri.getScheme())||!"pair".equals(uri.getHost()))throw new IllegalArgumentException("Scan an Eluno computer invitation.");
            String encoded=uri.getQueryParameter("data");
            if(encoded==null)throw new IllegalArgumentException("Incomplete invitation.");
            JSONObject invite=new JSONObject(new String(android.util.Base64.decode(encoded,android.util.Base64.URL_SAFE|android.util.Base64.NO_WRAP),java.nio.charset.StandardCharsets.UTF_8));
            if(invite.getInt("v")!=1||invite.getLong("expiresAt")<=System.currentTimeMillis()||!invite.getString("code").matches("[0-9]{6}"))throw new IllegalArgumentException("This invitation expired. Ask the computer for a new one.");
            PairingSecurity.fingerprint(invite.getString("fingerprint"));
            JSONArray endpoints=invite.getJSONArray("endpoints");
            if(endpoints.length()<1||endpoints.length()>12)throw new IllegalArgumentException("Invalid computer invitation.");
            for(int i=0;i<endpoints.length();i++)PairingSecurity.endpoint(endpoints.getString(i));
            CheckBox remember=new CheckBox(this);remember.setText("Remember this computer’s identity");
            new AlertDialog.Builder(this).setView(remember).setTitle("Connect to this computer?").setMessage("Approve this device in Eluno on the computer after connecting. Only media you select will be shared.").setNegativeButton("Cancel",null).setPositiveButton("Connect",(d,w)->connect(invite,remember.isChecked())).show();
        }catch(Exception error){message(error.getMessage());}
    }
    private void connect(JSONObject invite,boolean remember){
        String name=deviceName.getText().toString().trim();
        if(name.isEmpty()||name.length()>120){message("Enter a device name up to 120 characters.");return;}
        disconnect(); getPreferences(0).edit().putString("name",name).apply(); message("Connecting securely…");
        int generation=connectionGeneration;
        work(()->{
            ElunoApi connected=null; Exception last=null;
            JSONArray endpoints=invite.getJSONArray("endpoints");
            for(int i=0;i<endpoints.length();i++){
                ElunoApi attempt=new ElunoApi(endpoints.getString(i),invite.getString("fingerprint"));
                try {JSONObject device=attempt.json("POST","/api/devices",new JSONObject().put("name",name));attempt.token=device.getString("token");attempt.deviceId=device.getString("id");attempt.json("POST","/api/join",new JSONObject().put("code",invite.getString("code")));connected=attempt;break;}
                catch(Exception error){last=error;attempt.close();}
            }
            if(connected==null)throw new IOException("Could not reach your computer. Use the same Wi-Fi and scan a fresh invitation.",last);
            if(destroyed||generation!=connectionGeneration){try{connected.json("POST","/api/leave",null);}finally{connected.close();}return;}
            if(remember){JSONObject saved=new JSONObject(invite.toString());saved.remove("code");saved.remove("expiresAt");getPreferences(0).edit().putString("computer",saved.toString()).apply();}
            api=connected; poll(connected); message("Approve this device on your computer.");
        });
    }
    private void poll(ElunoApi client){polling.submit(()->{
        long version=-1;
        while(!destroyed&&api==client){
            try {
                if(!foreground){Thread.sleep(500);continue;}
                JSONObject state=client.json("GET","/api/events?since="+version,null);version=state.getLong("version");
                JSONArray requests=state.getJSONArray("reads");
                for(int i=0;i<requests.length();i++){JSONObject request=requests.getJSONObject(i);String id=request.getString("id");if(reading.add(id))work(()->{try{serve(client,request);}finally{reading.remove(id);}});}
                runOnUiThread(()->render(state,client));
            }catch(Exception error){if(api!=client)break;if(error instanceof ElunoApi.ApiException&&((ElunoApi.ApiException)error).status==401){runOnUiThread(()->{if(api==client)disconnect();});break;}message("Connection interrupted. Keep both devices open; Eluno will retry.");try{Thread.sleep(1500);}catch(InterruptedException stopped){break;}}
        }
    });}
    private void render(JSONObject state,ElunoApi client){
        if(api!=client||destroyed)return;
        room=state.optJSONObject("room");
        renderTransfers();
        if(room==null){closeViewer();sources.clear();for(File copy:sourceCopies.values())copy.delete();sourceCopies.clear();thumbnails.evictAll();getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);deviceName.setVisibility(View.VISIBLE);search.setVisibility(View.GONE);allowCopies.setVisibility(View.GONE);collectionName.setVisibility(View.GONE);if(favoritesOnly!=null)favoritesOnly.setVisibility(View.GONE);files.removeAllViews();status.setText(state.optBoolean("pending")?"Waiting for approval on your computer.":"Connection ended. Scan a new invitation to reconnect.");actions.removeAllViews();button(actions,state.optBoolean("pending")?"Cancel request":"Scan computer invitation",state.optBoolean("pending")?this::disconnect:this::scan);rememberedActions();rendered="";return;}
        String key=room.toString();if(key.equals(rendered))return;rendered=key;
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        JSONArray members=room.optJSONArray("members");StringBuilder names=new StringBuilder();
        for(int i=0;i<members.length();i++){JSONObject member=members.optJSONObject(i);if(names.length()>0)names.append(" ↔ ");names.append(member.optString("name"));if(!member.optBoolean("online"))names.append(" (offline)");}
        status.setText("Connected: "+names);nearbyText.setVisibility(View.GONE);deviceName.setVisibility(View.GONE);
        actions.removeAllViews();button(actions,"Add files",this::pick);button(actions,"Cancel file preparation",()->preparationCancelled=true);button(actions,"Disconnect",this::disconnect);
        search.setVisibility(View.VISIBLE);allowCopies.setVisibility(View.VISIBLE);collectionName.setVisibility(View.VISIBLE);favoritesOnly.setVisibility(View.VISIBLE);externalActions();renderFiles();
        if(viewedId!=null){boolean found=false;JSONArray items=room.optJSONArray("files");for(int i=0;i<items.length();i++)if(viewedId.equals(items.optJSONObject(i).optString("id")))found=true;if(!found){closeViewer();message("This item is no longer shared.");}}
    }
    private void renderFiles(){
        if(files==null)return;files.removeAllViews();if(room==null)return;
        JSONArray items=room.optJSONArray("files");String query=search.getText().toString().toLowerCase(Locale.ROOT);int matches=0;
        for(int i=0;i<items.length();i++){
            JSONObject item=items.optJSONObject(i);String owner="";JSONArray members=room.optJSONArray("members");for(int j=0;j<members.length();j++)if(item.optString("ownerId").equals(members.optJSONObject(j).optString("id")))owner=members.optJSONObject(j).optString("name");if(favoritesOnly.isChecked()&&!favorites.contains(item.optString("id")))continue;if(!(item.optString("name")+" "+item.optString("collection")+" "+owner).toLowerCase(Locale.ROOT).contains(query))continue;matches++;
            LinearLayout card=vertical(files);card.setPadding(0,dp(14),0,dp(14));text(card,item.optString("name"),18,true);text(card,String.format(Locale.ROOT,"%.1f MB",item.optLong("size")/1048576.0),12,false);
            Bitmap thumbnail=thumbnails.get(item.optString("id"));if(thumbnail!=null){ImageView preview=new ImageView(this);preview.setImageBitmap(thumbnail);preview.setContentDescription("Previously viewed photo");preview.setScaleType(ImageView.ScaleType.FIT_CENTER);card.addView(preview,new LinearLayout.LayoutParams(dp(96),dp(72)));}
            if(item.optString("type").startsWith("video/")||item.optString("type").startsWith("image/"))button(card,item.optString("type").startsWith("video/")?"Play":"View",()->open(item));
            if(!item.optString("collection").isEmpty())text(card,"Collection: "+item.optString("collection"),13,false);
            button(card,favorites.contains(item.optString("id"))?"Unfavorite":"Favorite",()->{String id=item.optString("id");if(!favorites.remove(id))favorites.add(id);renderFiles();});
            if(item.optBoolean("allowDownload"))button(card,"Save a copy",()->{pendingDownload=item.optString("id");downloadName=item.optString("name");Intent intent=new Intent(Intent.ACTION_CREATE_DOCUMENT).setType(item.optString("type")).addCategory(Intent.CATEGORY_OPENABLE).putExtra(Intent.EXTRA_TITLE,downloadName);startActivityForResult(intent,102);});
            if(api!=null&&api.deviceId.equals(item.optString("ownerId"))){
                button(card,"Send a copy",()->offer(item));
                button(card,"Move to collection",()->{EditText name=new EditText(this);name.setText(item.optString("collection"));new AlertDialog.Builder(this).setTitle("Collection name").setView(name).setNegativeButton("Cancel",null).setPositiveButton("Save",(dialog,which)->{String value=name.getText().toString();ElunoApi client=api;if(client!=null)work(()->client.json("PATCH","/api/files/"+item.getString("id"),new JSONObject().put("collection",value)));}).show();});
                button(card,item.optBoolean("allowDownload")?"Turn off saving copies":"Allow saving copies",()->work(()->api.json("PATCH","/api/files/"+item.getString("id"),new JSONObject().put("allowDownload",!item.optBoolean("allowDownload")))));
                button(card,"Stop sharing",()->work(()->{String id=item.getString("id");api.json("DELETE","/api/files/"+id,null);sources.remove(id);File copy=sourceCopies.remove(id);if(copy!=null)copy.delete();}));
            }
        }
        if(matches==0)text(files,query.isEmpty()?"Add something to share between your screens.":"No shared items match your search.",15,false);
    }


    private void rememberedActions(){
        if(actions==null||!getPreferences(0).contains("computer"))return;
        button(actions,"Reconnect to remembered computer",()->{
            EditText code=new EditText(this);code.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);code.setHint("Current six-digit code");
            new AlertDialog.Builder(this).setTitle("Verify and reconnect").setMessage("Enter the new code shown on your computer. Its saved identity will be checked; approval is still required.").setView(code).setNegativeButton("Cancel",null).setPositiveButton("Connect",(dialog,which)->{
                try{String value=code.getText().toString();if(!value.matches("[0-9]{6}"))throw new IOException("Enter six digits.");JSONObject saved=new JSONObject(getPreferences(0).getString("computer","{}"));saved.put("code",value);connect(saved,false);}catch(Exception error){message(error.getMessage());}
            }).show();
        });
        button(actions,"Forget remembered computer",()->{getPreferences(0).edit().remove("computer").apply();actions.removeAllViews();button(actions,"Scan computer invitation",this::scan);message("Remembered identity removed.");});
    }

    private void offer(JSONObject file){
        if(room==null||api==null)return;ElunoApi client=api;JSONArray members=room.optJSONArray("members");List<JSONObject> peers=new ArrayList<>();
        for(int i=0;i<members.length();i++){JSONObject peer=members.optJSONObject(i);if(!client.deviceId.equals(peer.optString("id"))&&peer.optBoolean("online"))peers.add(peer);}
        if(peers.isEmpty()){message("Connect another device first.");return;}
        String[] names=new String[peers.size()];for(int i=0;i<peers.size();i++)names[i]=peers.get(i).optString("name");
        new AlertDialog.Builder(this).setTitle("Send a copy to…").setItems(names,(dialog,index)->work(()->{client.json("POST","/api/transfers",new JSONObject().put("fileId",file.getString("id")).put("receiverId",peers.get(index).getString("id")));message("Offer sent. The receiver chooses where to save it.");})).setNegativeButton("Cancel",null).show();
    }
    private void renderTransfers(){
        if(transferList==null)return;transferList.removeAllViews();
        if(room==null){transfers.clear();return;}JSONArray items=room.optJSONArray("transfers");if(items==null||api==null)return;ElunoApi client=api;
        Set<String> active=new HashSet<>();
        if(items.length()>0)text(transferList,"Copies between devices",22,true);
        for(int i=0;i<items.length();i++){
            JSONObject t=items.optJSONObject(i);String id=t.optString("id"),state=t.optString("status");boolean terminal=Arrays.asList("completed","cancelled","declined").contains(state);if(!terminal)active.add(id);
            LinearLayout card=vertical(transferList);text(card,t.optString("name"),17,true);
            String destination="";JSONArray members=room.optJSONArray("members");for(int j=0;j<members.length();j++){JSONObject member=members.optJSONObject(j);if(member.optString("id").equals(t.optString("receiverId")))destination=member.optString("name");}
            text(card,String.format(Locale.ROOT,"To %s · %s · %.1f / %.1f MB",destination,state,t.optLong("bytes")/1048576.0,t.optLong("size")/1048576.0),13,false);
            ProgressBar progress=new ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal);progress.setMax(1000);progress.setProgress((int)(1000.0*t.optLong("bytes")/Math.max(1,t.optLong("size"))));progress.setContentDescription(t.optString("name")+" progress");card.addView(progress);
            if(!t.optString("error").isEmpty())text(card,t.optString("error"),13,false);
            if(client.deviceId.equals(t.optString("receiverId"))&&!terminal){
                Transfers.Job job=transfers.jobs.get(id);
                if(job!=null&&job.running)button(card,"Pause",()->job.paused=true);
                else button(card,job==null?"Choose folder & accept":"Resume",()->{if(job!=null)work(()->transfers.receive(client,t,null));else{incomingTransfer=t;startActivityForResult(new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE),103);}});
                if("offered".equals(state))button(card,"Decline",()->work(()->transfers.action(client,id,"decline",null)));
            }
            if(!terminal)button(card,"Cancel transfer",()->work(()->{transfers.action(client,id,"cancel",null);transfers.discard(id);}));
        }
        for(String id:new ArrayList<>(transfers.jobs.keySet()))if(!active.contains(id))transfers.discard(id);
    }

    private void pick(){Intent intent=new Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*").putExtra(Intent.EXTRA_ALLOW_MULTIPLE,true);startActivityForResult(intent,101);}
    @Override protected void onActivityResult(int requestCode,int resultCode,Intent data){
        IntentResult scan=IntentIntegrator.parseActivityResult(requestCode,resultCode,data);
        if(scan!=null){if(scan.getContents()!=null)invitation(scan.getContents());else message("Scanning cancelled. You can try again anytime.");return;}
        super.onActivityResult(requestCode,resultCode,data);
        if(resultCode!=RESULT_OK||data==null)return;
        if(requestCode==101){List<Uri> selected=new ArrayList<>();if(data.getClipData()!=null){for(int i=0;i<data.getClipData().getItemCount();i++)selected.add(data.getClipData().getItemAt(i).getUri());}else if(data.getData()!=null)selected.add(data.getData());confirmSelection(selected);}
        if(requestCode==103&&data.getData()!=null&&incomingTransfer!=null){JSONObject transfer=incomingTransfer; incomingTransfer=null; ElunoApi client=api; Uri folder=data.getData(); if(client!=null)work(()->transfers.receive(client,transfer,folder));}
        if(requestCode==102&&data.getData()!=null&&pendingDownload!=null){String id=pendingDownload;Uri destination=data.getData();work(()->save(id,destination));}
    }
    private void add(List<Uri> selected,boolean copies,String collection) throws Exception {
        ElunoApi client=api;if(client==null)throw new IOException("Connect your devices first.");
        if(selected.size()>50)throw new IOException("Select up to 50 items at a time.");
        JSONArray metadata=new JSONArray();List<File> staged=new ArrayList<>();
        try {
        for(Uri uri:selected){String name="",type=getContentResolver().getType(uri);long size=-1;
            try(Cursor cursor=getContentResolver().query(uri,new String[]{OpenableColumns.DISPLAY_NAME,OpenableColumns.SIZE},null,null,null)){if(cursor!=null&&cursor.moveToFirst()){name=cursor.getString(0);size=cursor.getLong(1);}}
            if(size<=0)throw new IOException("Choose a non-empty file stored on this device.");
            if(new StatFs(getCacheDir().getPath()).getAvailableBytes()<size+1048576)throw new IOException("Not enough device storage to prepare this selection.");
            File cached=File.createTempFile("eluno-source-",".media",getCacheDir());staged.add(cached);message("Preparing "+name+". Keep Eluno open.");
            try(InputStream input=getContentResolver().openInputStream(uri);OutputStream output=new FileOutputStream(cached)){if(input==null)throw new IOException("Source unavailable.");byte[] buffer=new byte[262144];int count;while((count=input.read(buffer))!=-1){if(preparationCancelled||api!=client)throw new IOException("Preparation cancelled.");output.write(buffer,0,count);}}
            if(cached.length()!=size)throw new IOException("Source changed during preparation. Select it again.");
            metadata.put(new JSONObject().put("name",name).put("type",type==null?"application/octet-stream":type).put("size",size).put("collection",collection).put("allowDownload",copies));
        }
        JSONArray added=client.json("POST","/api/files",new JSONObject().put("files",metadata)).getJSONArray("files");
        if(api!=client)throw new IOException("Connection ended during preparation.");
        for(int i=0;i<added.length();i++){String id=added.getJSONObject(i).getString("id");sources.put(id,Uri.fromFile(staged.get(i)));sourceCopies.put(id,staged.get(i));}
        message("Selected items are shared.");
        } catch(Exception error){for(File file:staged)file.delete();throw error;}
    }
    private void serve(ElunoApi client,JSONObject request) throws Exception {
        Uri uri=sources.get(request.getString("fileId"));if(uri==null)return;
        long start=request.getLong("start"),end=request.getLong("end"),length=end-start+1;
        if(start<0||length<1||length>262144)throw new IOException("Invalid media request.");
        try(ParcelFileDescriptor descriptor=getContentResolver().openFileDescriptor(uri,"r");FileInputStream input=new FileInputStream(descriptor.getFileDescriptor())){
            input.getChannel().position(start);byte[] bytes=new byte[(int)length];ByteBuffer buffer=ByteBuffer.wrap(bytes);
            while(buffer.hasRemaining()){if(input.getChannel().read(buffer)<0)throw new IOException("The selected file changed. Add it again.");}
            client.chunk(request.getString("id"),bytes);
        }
    }
    private boolean available(ElunoApi client,JSONObject item){if(api!=client||destroyed||room==null)return false;JSONArray items=room.optJSONArray("files");for(int i=0;i<items.length();i++)if(item.optString("id").equals(items.optJSONObject(i).optString("id")))return true;return false;}
    private void open(JSONObject item){ElunoApi client=api;if(client==null)return;int generation=++viewGeneration;work(()->{
        JSONObject access=client.json("POST","/api/files/"+item.getString("id")+"/open",null);
        String route=access.getString("url");
        if(item.getString("type").startsWith("video/"))runOnUiThread(()->{if(generation==viewGeneration&&available(client,item))showVideo(client,item,route);});
        else {
            File cached=File.createTempFile("eluno-photo-",".image",getCacheDir());
            try {
                try(Response response=client.http.newCall(client.request(route).get().build()).execute();OutputStream output=new FileOutputStream(cached)){if(!response.isSuccessful())throw new IOException("The photo is no longer available.");copy(response.body().byteStream(),output,50L*1024*1024);}
                BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeFile(cached.toString(),bounds);
                bounds.inSampleSize=1;while(bounds.outWidth/bounds.inSampleSize>2048||bounds.outHeight/bounds.inSampleSize>2048)bounds.inSampleSize*=2;
                bounds.inJustDecodeBounds=false;Bitmap bitmap=BitmapFactory.decodeFile(cached.toString(),bounds);if(bitmap==null)throw new IOException("This device cannot display that photo.");
                runOnUiThread(()->{if(generation==viewGeneration&&available(client,item)){thumbnails.put(item.optString("id"),Bitmap.createScaledBitmap(bitmap,96,72,true));renderFiles();showPhoto(item,bitmap);}else bitmap.recycle();});
            }finally{cached.delete();}
        }
    });}
    private LinearLayout viewer(JSONObject item){closeViewer();viewedId=item.optString("id");viewer=new Dialog(this);LinearLayout box=new LinearLayout(this);box.setOrientation(LinearLayout.VERTICAL);box.setPadding(dp(12),dp(12),dp(12),dp(12));text(box,item.optString("name"),18,true);button(box,"Close",this::closeViewer);viewer.setContentView(box);viewer.setOnDismissListener(d->{if(player!=null){if(viewedId!=null)playbackPositions.put(viewedId,player.getCurrentPosition());player.release();player=null;}viewedId=null;});viewer.show();viewer.getWindow().setLayout(-1,-1);return box;}
    private void showVideo(ElunoApi client,JSONObject item,String route){if(api!=client||destroyed)return;LinearLayout box=viewer(item);PlayerView view=new PlayerView(this);box.addView(view,new LinearLayout.LayoutParams(-1,0,1));player=new ExoPlayer.Builder(this).setMediaSourceFactory(new DefaultMediaSourceFactory(new OkHttpDataSource.Factory(client.http))).build();view.setPlayer(player);player.addListener(new Player.Listener(){@Override public void onPlayerError(PlaybackException error){message("Playback interrupted or format unsupported. Keep the sharing device open and try again.");Toast.makeText(MainActivity.this,"Playback interrupted. Close and try again.",Toast.LENGTH_LONG).show();}});player.setMediaItem(MediaItem.fromUri(client.origin+route));player.prepare();player.seekTo(playbackPositions.getOrDefault(item.optString("id"),0L));player.play();}
    private void showPhoto(JSONObject item,Bitmap bitmap){if(destroyed)return;LinearLayout box=viewer(item);ZoomImageView image=new ZoomImageView(this);image.setImageBitmap(bitmap);image.setScaleType(ImageView.ScaleType.FIT_CENTER);box.addView(image,new LinearLayout.LayoutParams(-1,0,1));LinearLayout controls=vertical(box);button(controls,"Previous photo",()->movePhoto(item.optString("id"),-1));button(controls,"Next photo",()->movePhoto(item.optString("id"),1));}
    private void movePhoto(String id,int direction){if(room==null)return;List<JSONObject> photos=new ArrayList<>();JSONArray items=room.optJSONArray("files");int current=0;for(int i=0;i<items.length();i++){JSONObject item=items.optJSONObject(i);if(item.optString("type").startsWith("image/")){if(id.equals(item.optString("id")))current=photos.size();photos.add(item);}}if(!photos.isEmpty())open(photos.get((current+direction+photos.size())%photos.size()));}
    private void closeViewer(){viewGeneration++;if(player!=null){if(viewedId!=null)playbackPositions.put(viewedId,player.getCurrentPosition());player.release();player=null;}if(viewer!=null){viewer.dismiss();viewer=null;}viewedId=null;}
    private void save(String id,Uri target)throws Exception{ElunoApi client=api;if(client==null)throw new IOException("Connect first.");String route=client.json("POST","/api/files/"+id+"/open",new JSONObject().put("purpose","download")).getString("url");message("Saving a copy…");try(Response response=client.http.newCall(client.request(route).get().build()).execute();OutputStream output=getContentResolver().openOutputStream(target,"wt")){if(!response.isSuccessful()||output==null)throw new IOException("This item could not be saved.");copy(response.body().byteStream(),output,Long.MAX_VALUE);}message("Copy saved. You can open it from your device’s Files app.");}
    private static void copy(InputStream input,OutputStream output,long limit)throws IOException{byte[] buffer=new byte[65536];long total=0;int n;while((n=input.read(buffer))!=-1){total+=n;if(total>limit)throw new IOException("This file is too large to display.");output.write(buffer,0,n);}}
    private void disconnect(){connectionGeneration++;if(transfers!=null)transfers.clear();if(transferList!=null)transferList.removeAllViews();playbackPositions.clear();thumbnails.evictAll();ElunoApi old=api;api=null;if(old!=null)jobs.submit(()->{try{old.json("POST","/api/leave",null);}catch(Exception ignored){}finally{old.close();}});sources.clear();for(File copy:sourceCopies.values())copy.delete();sourceCopies.clear();room=null;rendered="";closeViewer();if(files!=null)files.removeAllViews();if(actions!=null){actions.removeAllViews();button(actions,"Scan computer invitation",this::scan);rememberedActions();}if(search!=null)search.setVisibility(View.GONE);if(allowCopies!=null)allowCopies.setVisibility(View.GONE);if(collectionName!=null)collectionName.setVisibility(View.GONE);if(favoritesOnly!=null)favoritesOnly.setVisibility(View.GONE);favorites.clear();if(deviceName!=null)deviceName.setVisibility(View.VISIBLE);getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);message("Disconnected. Scan an invitation to connect again.");}
    private void startDiscovery(){if(discovery!=null||nsd==null)return;nearby.clear();
        discovery=new NsdManager.DiscoveryListener(){public void onDiscoveryStarted(String type){}public void onDiscoveryStopped(String type){}public void onStartDiscoveryFailed(String type,int code){message("Nearby discovery is unavailable. Scan the invitation on your computer.");}public void onStopDiscoveryFailed(String type,int code){}public void onServiceFound(NsdServiceInfo service){runOnUiThread(()->{nearby.add(service.getServiceName());nearbyText.setText("Nearby: "+String.join(", ",nearby)+". Scan the computer’s invitation to verify it.");});}public void onServiceLost(NsdServiceInfo service){runOnUiThread(()->{nearby.remove(service.getServiceName());nearbyText.setText(nearby.isEmpty()?"No nearby computers found. You can still scan an invitation.":"Nearby: "+String.join(", ",nearby));});}};
        try{WifiManager wifi=(WifiManager)getApplicationContext().getSystemService(WIFI_SERVICE);multicast=wifi.createMulticastLock("Eluno discovery");multicast.setReferenceCounted(false);multicast.acquire();nsd.discoverServices("_eluno._tcp.",NsdManager.PROTOCOL_DNS_SD,discovery);}catch(Exception error){nearbyText.setText("Scan the invitation shown on your computer.");}}
    private void stopDiscovery(){if(discovery!=null){try{nsd.stopServiceDiscovery(discovery);}catch(Exception ignored){}discovery=null;}if(multicast!=null&&multicast.isHeld())multicast.release();}
    @Override protected void onStart(){super.onStart();foreground=true;startDiscovery();}
    @Override protected void onStop(){foreground=false;if(transfers!=null)transfers.pauseAll();stopDiscovery();if(player!=null)player.pause();super.onStop();}
    @Override protected void onDestroy(){destroyed=true;disconnect();jobs.shutdown();polling.shutdownNow();super.onDestroy();}
    @Override public void onConfigurationChanged(Configuration configuration){super.onConfigurationChanged(configuration);}
}
