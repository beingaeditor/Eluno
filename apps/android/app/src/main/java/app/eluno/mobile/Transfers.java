package app.eluno.mobile;

import android.content.Context;
import android.net.Uri;
import android.os.StatFs;
import android.provider.DocumentsContract;
import org.json.JSONObject;
import okhttp3.Response;
import java.io.*;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/** Session-bound resumable copies. Destination URIs never leave this device. */
final class Transfers {
    static final class Job {
        final File partial; final Uri folder;
        volatile boolean running, paused, cancelled, saved;
        volatile long bytes;
        Job(File partial, Uri folder) { this.partial=partial; this.folder=folder; }
    }
    final Map<String,Job> jobs=new ConcurrentHashMap<>();
    private final Context context;
    Transfers(Context context){this.context=context;}
    JSONObject action(ElunoApi api,String id,String action,JSONObject extra)throws Exception {
        return api.json("PATCH","/api/transfers/"+id,(extra==null?new JSONObject():extra).put("action",action));
    }
    void receive(ElunoApi api,JSONObject transfer,Uri folder)throws Exception {
        String id=transfer.getString("id");long size=transfer.getLong("size");
        Job job=jobs.get(id);
        if(job==null){
            if(new StatFs(context.getCacheDir().getPath()).getAvailableBytes()<size+1048576)throw new IOException("Not enough space on this device. Free space and try again.");
            if(folder==null)throw new IOException("Choose a receiving folder first.");
            job=new Job(File.createTempFile("eluno-copy-",".part",context.getCacheDir()),folder);jobs.put(id,job);
        }
        synchronized(job){if(job.running)return;job.running=true;job.paused=false;}
        try {
            if("receiving".equals(transfer.optString("status")))action(api,id,"pause",null);
            String route=action(api,id,"offered".equals(transfer.optString("status"))?"accept":"resume",new JSONObject().put("bytes",job.bytes)).getString("url");
            try(RandomAccessFile output=new RandomAccessFile(job.partial,"rw")){
                output.seek(job.bytes);
                while(job.bytes<size){
                    if(job.paused||job.cancelled)throw new IOException("Paused. Keep the source shared and resume here.");
                    long end=Math.min(job.bytes+262144,size)-1;
                    try(Response response=api.http.newCall(api.request(route).header("Range","bytes="+job.bytes+"-"+end).get().build()).execute()){
                        if(!response.isSuccessful()||response.body()==null)throw new IOException("Source unavailable. Keep both devices open and resume.");
                        byte[] bytes=response.body().bytes();
                        if(bytes.length!=end-job.bytes+1)throw new IOException("The source changed. Cancel and send it again.");
                        if(job.cancelled)throw new IOException("Transfer cancelled.");
                        output.write(bytes);job.bytes+=bytes.length;
                        action(api,id,"progress",new JSONObject().put("bytes",job.bytes));
                    }
                }
                output.getFD().sync();
            }
            if(job.paused||job.cancelled)throw new IOException("Transfer paused or cancelled.");
            if(!job.saved){
                Uri parent=DocumentsContract.buildDocumentUriUsingTree(job.folder,DocumentsContract.getTreeDocumentId(job.folder));
                // Providers choose a unique name rather than opening an existing document for overwrite.
                Uri target=DocumentsContract.createDocument(context.getContentResolver(),parent,transfer.getString("type"),transfer.getString("name"));
                if(target==null)throw new IOException("Could not create the destination file. Choose another folder.");
                try(InputStream input=new FileInputStream(job.partial);OutputStream output=context.getContentResolver().openOutputStream(target,"w")){
                    if(output==null)throw new IOException("Destination is not writable.");
                    byte[] bytes=new byte[65536];int count;
                    while((count=input.read(bytes))!=-1){if(job.cancelled||job.paused)throw new IOException("Saving interrupted. Resume to save the copy.");output.write(bytes,0,count);}
                }catch(Exception error){try{DocumentsContract.deleteDocument(context.getContentResolver(),target);}catch(Exception ignored){}throw error;}
                job.saved=true;
            }
            action(api,id,"complete",null);job.partial.delete();jobs.remove(id);
        }catch(Exception error){
            if(!job.cancelled)try{action(api,id,"pause",new JSONObject().put("error",error.getMessage()));}catch(Exception ignored){}
            throw error;
        }finally{job.running=false;if(job.cancelled){job.partial.delete();jobs.remove(id);}}
    }
    void pauseAll(){for(Job job:jobs.values())job.paused=true;}
    void discard(String id){Job job=jobs.get(id);if(job==null)return;job.cancelled=true;if(!job.running){job.partial.delete();jobs.remove(id);}}
    void clear(){for(String id:new ArrayList<>(jobs.keySet()))discard(id);}
}
