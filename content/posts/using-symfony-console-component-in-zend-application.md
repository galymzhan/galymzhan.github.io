---
title: Using Symfony Console Component in Zend application
created_at: 2012-02-14 21:53
kind: article
description: Instead of reinventing the wheel, have a look at Symfony Console Component for all of your CLI tasks.
---

Zend Framework is good when it comes to web requests, involving controllers with their actions, but usually most web applications today have another entry point: running from console. Some examples of console tasks: clearing up cache, sending emails, seeding a database, extracting/merging translatable strings and generally any kind of batch jobs. At first, I've kept a directory of runnable scripts for this, but after some time, I realized the need to unify and organize this messy collection of scripts.
[Symfony Console Component](http://symfony.com/doc/2.0/components/console.html) elegantly solves this kind of problem, providing solid platform for building CLI applications. Being one of the core components of [Symfony2](http://symfony.com) framework, it's already intensively used in the framework itself and other PHP projects. If you are new to Symfony Console, I suggest checking out these links:

* [The Console Component](http://symfony.com/doc/2.0/components/console.html)
* [Building CLI Apps with Symfony Console Component](http://dev.umpirsky.com/building-cli-apps-with-symfony-console-component/)

Let's see how could we integrate it into Zend application. Suppose we have a Zend application with the structure similar to the [recommended one](http://framework.zend.com/manual/en/project-structure.project.html) and `~/cli-show` is a root directory. Symfony Console requires PHP >= 5.3, version of Zend framework being used is 1.11.8.

## Installing Symfony Console

I'm going to install it from Git. In real project, we'll probably use git's submodule functionality or download the archive from Github and unzip it, but for the sake of simplicity, let's just clone it now.

```bash
[/]$ cd ~/cli-show
[cli-show]$ mkdir -p library/Symfony/Component
[cli-show]$ git clone https://github.com/symfony/Console.git library/Symfony/Component/Console
```

Also, to properly autoload Symfony classes we'll have to register Symfony namespace (assuming `Zend_Loader_Autoloader` is used for autoloading).

```ini
[production]
; Add this line
autoloaderNamespaces.symfony = "Symfony"
```

## Testing installation

Symfony Console itself has some basic commands. Let's try running them. Create the file `console` under `scripts` directory, and make it executable.

```bash
[cli-show]$ mkdir scripts && touch scripts/console && chmod a+x scripts/console
```

This script will be the entry point for all console commands. We'll use the default `Symfony\Component\Console\Application` class provided by Symfony Console. Contents of our script:

```php
#!/usr/bin/env php
<?php
// Define path to application directory
defined('APPLICATION_PATH')
    || define('APPLICATION_PATH', realpath(dirname(__FILE__) . '/../application'));

// Define application environment
defined('APPLICATION_ENV')
    || define('APPLICATION_ENV', (getenv('APPLICATION_ENV') ? getenv('APPLICATION_ENV') : 'production'));

// Ensure library/ is on include_path
set_include_path(implode(PATH_SEPARATOR, array(
    realpath(APPLICATION_PATH . '/../library'),
    get_include_path(),
)));

/** Zend_Application */
require_once 'Zend/Application.php';

// Create application and bootstrap it
$application = new Zend_Application(
    APPLICATION_ENV,
    APPLICATION_PATH . '/configs/application.ini'
);
$application->bootstrap();

$cliApp = new \Symfony\Component\Console\Application(
    'Example console application', '1.0'
);
$cliApp->run();
```

This code is very similar to the code in `index.php` and we should avoid duplicating it, but for now let's just try it:

```bash
[cli-show]$ scripts/console
```

A nice looking output should appear, telling you possible command-line switches and commands.

![Default Symfony console application](/images/cli-show-1.png)

## Introducing Zend application

Right now CLI script doesn't know anything about existing Zend application. In order to properly use business-logic of our application, we have into set correct application environment, instantiate instance of Zend_Application and bootstrap it. Also, we should move bootstrapping code to separate file and reuse it between our CLI script, `index.php` and `index-test.php` files. Considering all of this, let's rewrite the script:

```php
#!/usr/bin/env php
<?php
require_once 'Zend/Loader/Autoloader.php';
$autoloader = Zend_Loader_Autoloader::getInstance();
$autoloader->registerNamespace('Symfony');
$input = new \Symfony\Component\Console\Input\ArgvInput;
// Try to get APPLICATION_ENV from environment variable
$env = getenv('APPLICATION_ENV');
if (!$env) {
    // Get APPLICATION_ENV from command-line option or set to 'development' by default
    $env = $input->getParameterOption('--env', 'development');
}
define('APPLICATION_ENV', $env);
$zendApp = require_once __DIR__ . '/../bootstrapper.php';
$cliApp = new \Symfony\Component\Console\Application(
    'Example console application', '1.0'
);
$cliApp->run();
```

We need to require and configure Zend's autoloader by hand, because our application isn't yet bootstrapped at this point. Zend's library should be in include path, otherwise we must manually add it using `set_include_path`. We use `Symfony\Component\Console\Input\ArgvInput` to get application's environment from command-line. If it's not passed, 'development' environment will be used. Note that we might want to save `$zendApp` somewhere in order to reference to it in the future. I see 2 options:

* put it into `Zend_Registry`
* create a subclass of `Symfony\Component\Console\Application` which will receive instance of `Zend_Application` as a constructor argument

As you might see, we've moved bootstrapping code into separate `bootstrapper.php` file under project's root. It might look like this:

```php
<?php
// Define path to application directory
define('APPLICATION_PATH', __DIR__ . '/application');

// Ensure library/ is on include_path
set_include_path(implode(PATH_SEPARATOR, array(
    realpath(APPLICATION_PATH . '/../library'),
    get_include_path(),
)));

require_once 'Zend/Application.php';

// Create application
// APPLICATION_ENV should be already defined at this point
$application = new Zend_Application(
    APPLICATION_ENV,
    APPLICATION_PATH . '/configs/application.ini'
);
// Bootstrap and return it
return $application->bootstrap();
```

`index.php` will be using it too:

```php
<?php
// Define application environment
defined('APPLICATION_ENV')
    || define('APPLICATION_ENV', (getenv('APPLICATION_ENV') ? getenv('APPLICATION_ENV') : 'production'));
$application = require __DIR__ . '/../bootstrapper.php';
$application->run();
```

## Writing console commands

Every command is a subclass of `Symfony\Component\Console\Command\Command`. In order to keep commands organized, we can add a new resource type called "command" by modifying Bootstrap class:

```php
<?php

class Bootstrap extends Zend_Application_Bootstrap_Bootstrap
{
  // skipping

    protected function _initResourceLoader()
    {
        $this->_resourceLoader->addResourceType('command', 'commands', 'Command');
    }
}
```

Now we could create `application/commands` directory and add our commands there. For example, here is the Time command:

```php
<?php
use Symfony\Component\Console\Command\Command,
    Symfony\Component\Console\Input\InputInterface,
    Symfony\Component\Console\Output\OutputInterface;

class Application_Command_Time extends Command
{
    protected function configure()
    {
        $this
            ->setName('app:time')
            ->setDescription('What time is it?')
            ->setHelp('What time is it? This command answers exactly this question');
    }

    protected function execute(InputInterface $input, OutputInterface $output)
    {
        $time = date('H:i:s');
        $output->writeln('Current time: <info>%s</info>', $time);
    }
}
```

After creating command, we must add it to the list of known commands by calling `addCommands`. This is true for all commands (Doctrine ORM, for instance, has many console commands):

```php
<?php
// ... skipping lines
$cliApp = new \Symfony\Component\Console\Application(
    'Example console application', '1.0'
);
$cliApp->addCommands(array(
    // Application commands
    new Application_Command_Time,

    // Commands from other libraries
    new \Doctrine\ORM\Tools\Console\Command\ClearCache\ResultCommand(),
    new \Doctrine\ORM\Tools\Console\Command\ClearCache\QueryCommand(),
));
$cliApp->run();
```

Let's see what time is it:

```bash
[cli-show]$ scripts/console app:time
Current time: 18:12:02
```

## Use it

Symfony Console is a really great component. It's decoupled, so you can use it in any kind of application. Even if you aren't going to write your own commands, you can still use this approach to integrate any library which uses Symfony Console, such as Doctrine ORM. And if you're on PHP>=5.3 and facing a problem of writing console task, you should definitely use it.
