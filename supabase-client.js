(function(){
  let clientPromise = null;
  let client = null;

  window.loadLapakSupabase = function(){
    if(client) return Promise.resolve(client);
    if(clientPromise) return clientPromise;

    const config = window.LAPAK_SUPABASE_CONFIG;
    if(!config || !/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(config.url || '') ||
      !config.anonKey || config.anonKey === 'YOUR_SUPABASE_ANON_KEY'){
      return Promise.reject(new Error('Konfigurasi kelas belum diisi. Hubungi pengelola aplikasi.'));
    }

    clientPromise = new Promise(function(resolve, reject){
      const script = document.createElement('script');
      script.src = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2';
      script.async = true;
      script.onload = function(){
        if(!window.supabase || !window.supabase.createClient){
          clientPromise = null;
          reject(new Error('Pustaka Supabase tidak berhasil dimuat.'));
          return;
        }
        client = window.supabase.createClient(config.url, config.anonKey);
        resolve(client);
      };
      script.onerror = function(){
        script.remove();
        clientPromise = null;
        reject(new Error('Tidak dapat memuat layanan kelas. Periksa koneksi internet.'));
      };
      document.head.appendChild(script);
    });

    return clientPromise;
  };
})();
