#!/usr/bin/php
<?php
  declare(strict_types=1);
  echo 'Checking NEMS Version... ';
  $nemsver = shell_exec('/usr/local/bin/nems-info nemsver');
  echo $nemsver . PHP_EOL;
  // NEMS 1.5 includes packages that are needed for the encryption aspects of NEMS Cloud.
  // Can't continue if on an older version of NEMS Linux.
  if ($nemsver < 1.5) die('NEMS Cloud requires NEMS 1.5+. Please upgrade.' . PHP_EOL);
  echo 'Checking if this NEMS server is authorized to use NEMS Cloud... ';
  $cloudauth = shell_exec('/usr/local/bin/nems-info cloudauth');
  if ($cloudauth == 1) {
  echo 'Yes.' . PHP_EOL;
  echo 'Loading NEMS state information... ';
  $nems = new stdClass();
  $nems->state = new stdClass();
  $nems->state->raw = trim(shell_exec('/usr/local/bin/nems-info state'));
  $nems->hwid = trim(shell_exec('/usr/local/bin/nems-info hwid'));
  $tmp = file('/usr/local/share/nems/nems.conf');

  $nems->osbkey = '';
  $nems->osbpass = '';
  if (is_array($tmp)) {
    foreach($tmp as $line) {
      if (strstr($line,'=')) {
        $tmp2 = explode('=',$line);
        if (isset($tmp2[1])) {
          $tmp2[0] = trim($tmp2[0]);
          $tmp2[1] = trim($tmp2[1]);
        }
        if ($tmp2[0] == 'osbkey') {
          $nems->osbkey = $tmp2[1];
        }
        if ($tmp2[0] == 'osbpass') {
          $nems->osbpass = $tmp2[1];
        }
        unset($tmp,$tmp2);
      }
    }
  }
  if (isset($nems->state->raw) && isset($nems->hwid) && isset($nems->osbkey) && isset($nems->osbpass)) {
    echo 'Done.' . PHP_EOL;
    echo 'Encrypting data for transmission... ';
    if (strlen($nems->hwid) > 0 && strlen($nems->osbkey) > 0 && strlen($nems->osbpass) > 0) {
      $nems->state->encrypted = safeEncrypt($nems->state->raw,getKeyFromPassword($nems->osbpass,'::'.$nems->hwid.'::'.$nems->osbkey.'::',32));
    }
  }

  if (isset($nems->state->encrypted) && strlen($nems->state->encrypted) > 0) {
    // proceed, but only if the data is encrypted
    echo 'Done.' . PHP_EOL;
    echo 'Sending data... ';

    // creating a new payload to avoid there EVER being a possibility of accidentally transmitting the raw data
    $datatransfer = array(
      'state'=>$nems->state->encrypted,
      'hwid'=>$nems->hwid,
      'osbkey'=>$nems->osbkey // notice, I am NOT sending the osbpass - that is for you only
    );

    $ch = curl_init('https://nemslinux.com/api/cloud/');
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLINFO_HEADER_OUT, true);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, $datatransfer);
    $result = curl_exec($ch);
    echo $result . PHP_EOL;

    curl_close($ch);

  } else {
    echo 'Failed.' . PHP_EOL;
    echo 'Did you activate your NEMS Cloud account? Aborted.';
  }


} else {
  echo 'No.';
}
echo PHP_EOL;

/**
 * Encrypt a message
 * 
 * @param string $message - message to encrypt
 * @param string $key - encryption key
 * @return string
 * @throws RangeException
 */
function safeEncrypt(string $message, string $key): string
{
    if (mb_strlen($key, '8bit') !== SODIUM_CRYPTO_SECRETBOX_KEYBYTES) {
        throw new RangeException('Key is not the correct size (must be 32 bytes).');
    }
    $nonce = random_bytes(SODIUM_CRYPTO_SECRETBOX_NONCEBYTES);

    $cipher = base64_encode(
        $nonce.
        sodium_crypto_secretbox(
            $message,
            $nonce,
            $key
        )
    );
    sodium_memzero($message);
    sodium_memzero($key);
    return $cipher;
}

/**
 * Decrypt a message
 * 
 * @param string $encrypted - message encrypted with safeEncrypt()
 * @param string $key - encryption key
 * @return string
 * @throws Exception
 */
function safeDecrypt(string $encrypted, string $key): string
{   
    $decoded = base64_decode($encrypted);
    $nonce = mb_substr($decoded, 0, SODIUM_CRYPTO_SECRETBOX_NONCEBYTES, '8bit');
    $ciphertext = mb_substr($decoded, SODIUM_CRYPTO_SECRETBOX_NONCEBYTES, null, '8bit');

    $plain = sodium_crypto_secretbox_open(
        $ciphertext,
        $nonce,
        $key
    );
    if (!is_string($plain)) {
        throw new Exception('Invalid MAC');
    }
    sodium_memzero($ciphertext);
    sodium_memzero($key);
    return $plain;
}

/**
 * Get an AES key from a static password and a secret salt
 * 
 * @param string $password Your weak password here
 * @param int $keysize Number of bytes in encryption key
 */
function getKeyFromPassword($password, $salt, $keysize = 16)
{
    return hash_pbkdf2(
        'sha256',
        $password,
        $salt,
        100000, // Number of iterations
        $keysize,
        true
    );
}

?>