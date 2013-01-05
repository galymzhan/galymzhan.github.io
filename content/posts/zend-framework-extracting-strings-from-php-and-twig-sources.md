---
title: "Zend Framework: Extracting strings from PHP and Twig sources"
created_at: 2012-02-05 15:04
kind: article
description: How to implement custom mechanism of extracting translatable strings from your source code, since there is no standard way.
---

In the last project I worked on, we used `Zend_Translate` with array adapter. There were three main problems with extracting translatable strings from sources:

- We were unable to use [Poedit](http://www.poedit.net/), because we didn't use Gettext adapter
- All of our forms use default translator, so form definitions looks like this:

```php
<?php
class Application_Forms_Register extends Zend_Form
{
  public function init()
  {
    $this->addElement('text', 'name', array(
        'label' => 'Your name', // This needs to be extracted
        'required' => true,
    ));
    $this->addElement('text', 'email', array(
        'label' => 'E-mail', // This too
        'required' => true,
        'validators' => array('EmailAddress'),
    ));
    $this->addElement('submit', 'submit');
    $this->submit->setLabel('Register'); // And this
  }
}
```

- Twig is used for templating, so we needed to extract translations from .twig files as well:

```jinja
{{ t('Fill in the following form') }}
```

Note that we wrote custom extension for Twig, which provides `t` function for translation. Essentially, it just delegates calls to `Zend_Translate`.

Considering this, I decided to write a custom extractor. Since we have 2 main sources of translatable strings (Twig templates and PHP files), let's define common interface:

```php
<?php

/**
 * Common interface for different message extractors
 */
interface ExtractorInterface
{
    /**
     * Extracts messages from given resource. $resource is something that is
     * specific to message extractor, Twig extractor will treat it as a
     * template name, whereas for PHP it is a filename
     */
    public function extract($resource);

    /**
     * Sets a callback which will be called whenever a warning message is going
     * to be issued
     */
    public function setWarningListener(\Closure $listener);
}
```

We'll call `extract` for given resource and it should return all translatable strings from it. `setWarningListener` allows setting custom callback which will be fired whenever something wrong happens during extracting. Let's start from Twig implementation:

```php
<?php

/**
 * Extracts messages from Twig templates
 */
class TwigExtractor extends AbstractExtractor implements ExtractorInterface, \Twig_NodeVisitorInterface
{
    protected $extracted;

    public function __construct(\Twig_Environment $env)
    {
        $this->env = $env;
        // Registers itself as a node visitor
        $this->env->addNodeVisitor($this);
    }

    /**
     * Defined by ExtractorInterface
     *
     * @param $resource Template name
     */
    public function extract($resource)
    {
        $this->extracted = array();
        $this->resource = $resource;
        try {
            // Parse template
            $this->env->parse(
                $this->env->tokenize(
                    $this->env->getLoader()->getSource($resource),
                    $resource
                )
            );
        } catch (\Twig_Error_Syntax $e) {
            $this->warning(
                'Twig has thrown syntax error ' . $e->getMessage(),
                $e->getTemplateLine()
            );
        }
        $this->resource = '';
        return $this->extracted;
    }

    /**
     * Defined by Twig_NodeVisitorInterface
     *
     * Extracts messages from calls to the translate function.
     */
    public function enterNode(\Twig_NodeInterface $node, \Twig_Environment $env)
    {
        if ($node instanceof \Twig_Node_Expression_Function) {
            if ($node->getAttribute('name') == 't') {
                $args = $node->getNode('arguments')->getIterator();
                $lineno = $node->getLine();
                if (!isset($args[0])) {
                    $this->warning('Translate function requires at least one argument', $lineno);
                } else {
                    if ($args[0] instanceof \Twig_Node_Expression_Constant) {
                        // Singular translation
                        $this->extracted[] = array(
                            'message' => $args[0]->getAttribute('value'),
                            'lineno' => $lineno,
                        );
                    } elseif ($args[0] instanceof \Twig_Node_Expression_Array) {
                        // Plural translation
                        // There must be at least three arguments
                        if (count($args[0]) < 3) {
                            $this->warning('Plural translation requires at least three elements', $lineno);
                        } else {
                            $messages = array();
                            $elements = $args[0]->getIterator();
                            for ($i = 0; $i < count($elements) - 2; $i++) {
                                if (!$elements[$i] instanceof \Twig_Node_Expression_Constant) {
                                    $messages = array();
                                    break;
                                }
                                $messages[] = $elements[$i]->getAttribute('value');
                            }
                            if (empty($messages)) {
                                $this->warning('All elements of plural translation must be constant values', $lineno);
                            } else {
                                $this->extracted[] = array(
                                    'message' => $messages,
                                    'lineno' => $lineno,
                                );
                            }
                        }
                    } else {
                        $this->warning('First argument of translate function must be either string or array', $lineno);
                    }
                }
            }
        }
        return $node;
    }

    /**
     * Defined by Twig_NodeVisitorInterface
     */
    public function leaveNode(\Twig_NodeInterface $node, \Twig_Environment $env)
    {
        return $node;
    }

    /**
     * Defined by Twig_NodeVisitorInterface
     */
    public function getPriority()
    {
        return 0;
    }
}
```

Twig allows you to write and register your custom node visitors. This is what we have done in the constructor. As you might know, after parsing template file, Twig creates a structure called "abstract syntax tree" - hierarchical tree of nodes. Each node represents something in template's source code: assignment, arithmetical expression or possibly an include statement. After parsing, Twig traverses this abstract tree of nodes, calling magic method for each of its registered visitors and passing current node as an argument. This method is defined by `Twig_NodeVisitorInterface` as `enterNode`. Among other types of nodes, there is a node called "function expression", which is a target of our interest. If we encounter such node, we'll see whether its name equal to `t` (which is the translator function), and in such case, extract its arguments. There is one more thing: in case of plural translations `t` receives array of strings, not just one string. So there is an additional logic covering that case too.

`AbstractExtractor`, which is extended by `TwigExtractor` provides some base methods like `warning` and is trivial to implement.

Now let's examine what we could do with PHP files. As there were a wrapper class around `Zend_Translate`, all of our translate calls looked like this:

```php
<?php
use Application\Translate\Translate as t;
// ...
$title = t::t('Incoming messages');
$message = t::t(array('You have %d message', 'You have %d messages'), $c);
```

Also, we needed to extract strings in forms `setLabel(something)` and `'label' => something`. Having armed with this information, I wrote a parser. Parser is a finite-state machine that receives a stream of PHP tokens. Here it is:

```php
<?php
/**
 * Extracts messages from PHP source files
 */
class PhpExtractor extends AbstractExtractor implements ExtractorInterface
{
    protected $extracted, $tokens, $state;

    /**
     * Defined by ExtractorInterface
     */
    public function extract($resource)
    {
        $this->extracted = array();
        $this->resource = $resource;
        $this->tokens = token_get_all(file_get_contents($resource));
        $this->tcount = count($this->tokens);
        $this->parseTokens();
        $this->resource = '';
        return $this->extracted;
    }

    /**
     * Skips all whitespaces (\n, \r, spaces, etc) starting from position $p.
     * @return position at which parsing could be continued.
     */
    protected function skipWhitespaces($p)
    {
        while ($p < $this->tcount) {
            if (is_array($this->tokens[$p]) && $this->tokens[$p][0] == T_WHITESPACE) {
                $p++;
                continue;
            }
            if (is_string($this->tokens[$p]) && ctype_space($this->tokens[$p])) {
                $p++;
                continue;
            }
            break;
        }
        return $p;
    }

    /**
     * Tries to parse 't::t(' tokens starting from position $p.
     * @return if successful, returns position at which parsing could be
     *  continued, false otherwise
     */
    protected function parseTCall($p)
    {
        if (!is_array($this->tokens[$p]) or $this->tokens[$p][0] != T_STRING
            or $this->tokens[$p][1] != 't'
        ) {
            return false;
        }
        if (!is_array($this->tokens[$p + 1]) or $this->tokens[$p + 1][0] != T_DOUBLE_COLON) {
            return false;
        }
        if (!is_array($this->tokens[$p + 2]) or $this->tokens[$p + 2][0] != T_STRING
            or $this->tokens[$p + 2][1] != 't'
        ) {
            return false;
        }
        $p = $this->skipWhitespaces($p + 3);
        if (is_string($this->tokens[$p]) && $this->tokens[$p] == '(') {
            return $p + 1;
        }
        return false;
    }

    /**
     * Tries to parse 'array(' tokens (keyword and opening parenthesis)
     * @return position at which parsing could be continued,
     *  false otherwise
     */
    protected function parseArray($p)
    {
        if (!is_array($this->tokens[$p]) or $this->tokens[$p][0] != T_ARRAY) {
            return false;
        }
        $p = $this->skipWhitespaces($p + 1);
        if (is_string($this->tokens[$p]) && $this->tokens[$p] == '(') {
            return $p + 1;
        }
        return false;
    }

    /**
     * Tries to parse array contents. Treats everything till ')'
     * separated by commas as array elements.
     * @return array with the following keys:
     *   'pos' => position at which parsing could be continued
     *   'items' => array elements
     */
    protected function parseArrayContents($p)
    {
        $items = array();
        while ($p < $this->tcount) {
            $p = $this->skipWhitespaces($p);
            if (is_array($this->tokens[$p])) {
                $items[] = $this->tokens[$p];
            } else {
                if ($this->tokens[$p] == ')') {
                    break;
                } elseif ($this->tokens[$p] != ',') {
                    $items[] = $this->tokens[$p];
                }
            }
            $p++;
        }
        return array('pos' => $p, 'items' => $items);
    }

    /**
     * Tries to parse '"label" =>' tokens starting from position $p.
     * @return if successful, returns position at which parsing could be
     *  continued, false otherwise
     */
    protected function parseLabelInArray($p)
    {
        if (!$this->isString($this->tokens[$p])) {
            return false;
        }
        if ($this->evaluateString($this->tokens[$p]) != 'label') {
            return false;
        }
        $p = $this->skipWhitespaces($p + 1);
        if (!is_array($this->tokens[$p]) or $this->tokens[$p][0] != T_DOUBLE_ARROW) {
            return false;
        }
        return $p + 1;
    }

    /**
     * Tries to parse '->setLabel(' tokens starting from position $p.
     * @return if successful, returns position at which parsing could be
     *  continued, false otherwise
     */
    protected function parseSetLabelCall($p)
    {
        if (!is_array($this->tokens[$p]) or $this->tokens[$p][0] != T_OBJECT_OPERATOR) {
            return false;
        }
        $p = $this->skipWhitespaces($p + 1);
        if (!is_array($this->tokens[$p]) or $this->tokens[$p][0] != T_STRING
            or $this->tokens[$p][1] != 'setLabel'
        ) {
            return false;
        }
        $p = $this->skipWhitespaces($p + 1);
        if (is_string($this->tokens[$p]) && $this->tokens[$p] == '(') {
            return $p + 1;
        }
        return false;
    }

    protected function isString($token)
    {
        return (is_array($token) && $token[0] == T_CONSTANT_ENCAPSED_STRING);
    }

    /**
     * Finds line number for the token at position $p. If line number for this
     * token is unknown, it tries previous token
     * @return line number
     */
    protected function lineno($p)
    {
        do {
            if (is_array($this->tokens[$p])) {
                return $this->tokens[$p][2];
            }
        } while (--$p > 0);
        return 1;
    }

    /**
     * Evaluates string token. Unquotes quoted string, strips backslashes.
     * @return string contents of the token
     */
    protected function evaluateString($token)
    {
        $s = is_array($token) ? (string)$token[1] : (string)$token;
        $s = stripslashes($s);
        $length = mb_strlen($s, 'UTF-8');
        $first = mb_substr($s, 0, 1, 'UTF-8');
        $last = mb_substr($s, $length - 1, 1, 'UTF-8');
        if ($length > 1 && $first == '"' && $last = '"') {
            $s = mb_substr($s, 1, $length - 2, 'UTF-8');
        }
        if ($length > 1 && $first == "'" && $last == "'") {
            $s = mb_substr($s, 1, $length - 2, 'UTF-8');
        }
        return $s;
    }


    protected function parseTokens()
    {
        $state = $i = 0;
        while ($i < $this->tcount) {
            switch ($state) {
                case 0:
                    // Expecting one of the following:
                    // - function call t::t
                    // - label definition in array 'label' => 'Your password'
                    // - method call ->setLabel
                    if (($p = $this->parseTCall($i)) !== false) {
                        $i = $p;
                        $state = 1;
                    } elseif (($p = $this->parseLabelInArray($i)) !== false) {
                        $i = $p;
                        $state = 3;
                    } elseif (($p = $this->parseSetLabelCall($i)) !== false) {
                        $i = $p;
                        $state = 3;
                    } else {
                        $i++;
                    }
                    break;

                case 1:
                    // Expecting string or array keyword
                    $i = $this->skipWhitespaces($i);
                    if (($p = $this->parseArray($i)) !== false) {
                        $i = $p;
                        $state = 2;
                    } elseif ($this->isString($this->tokens[$i])) {
                        // Singular translation
                        $this->extracted[] = array(
                            'message' => $this->evaluateString($this->tokens[$i]),
                            'lineno' => $this->lineno($i),
                        );
                        $i++;
                        $state = 0;
                    } else {
                        $this->warning(
                            'First argument of translate function must be either string or array',
                            $this->lineno($i)
                        );
                        $i++;
                        $state = 0;
                    }
                    break;

                case 2:
                    // Expecting contents of array for plural translation
                    $array = $this->parseArrayContents($i);
                    if (count($array['items']) < 3) {
                        $this->warning(
                            'Plural translation requires at least three elements',
                            $this->lineno($i)
                        );
                    } else {
                        $messages = array();
                        foreach (array_slice($array['items'], 0, -2) as $item) {
                            if ($this->isString($item)) {
                                $messages[] = $this->evaluateString($item);
                            } else {
                                $messages = array();
                                break;
                            }
                        }
                        if (empty($messages)) {
                            $this->warning(
                                'All elements of plural translation must be constant values',
                                $this->lineno($i)
                            );
                        } else {
                            $this->extracted[] = array(
                                'message' => $messages,
                                'lineno' => $this->lineno($i),
                            );
                        }
                    }
                    $i = $array['pos'] + 1;
                    $state = 0;
                    break;

                case 3:
                    // Expecting constant string ('label' => 'string')
                    // or setLabel('string')
                    $i = $this->skipWhitespaces($i);
                    if ($this->isString($this->tokens[$i])) {
                        $this->extracted[] = array(
                            'message' => $this->evaluateString($this->tokens[$i]),
                            'lineno' => $this->lineno($i),
                        );
                    } else {
                        $this->warning('Label must be a constant string', $this->lineno($i));
                    }
                    $i++;
                    $state = 0;
                    break;
            }
        }
    }
}
```

As you can see, we used [`token_get_all`](http://php.net/token_get_all) to get stream of tokens from given file. Because we're skipping whitespaces where possible, this parser could handle these cases:

```php
<?php
t :: t('abc');
t
::
  t('def');
array('label' => "something");
'label'
=> "something",
$f->
setLabel("something")
```
and so on.

Example usage:

```php
<?php
$listener = function($resource, $message, $lineno) {
  echo sprintf('Warning in %s at line %d: %s', $resource, $lineno, $message);
};
$extractor = new PhpExtractor;
$extractor->setWarningListener($listener);
// Recursively loop over all PHP files under APPLICATION_PATH directory
$dirIter = new \RecursiveDirectoryIterator(APPLICATION_PATH);
foreach (new \RecursiveIteratorIterator($dirIter) as $filename => $fileinfo) {
    if ($fileinfo->isFile() && pathinfo($fileinfo->getFilename(), PATHINFO_EXTENSION) === 'php') {
        $result[$filename] = $extractor->extract($filename);
    }
}
print_r($result);
```

This is not the end, because you'll need to merge extracted messages into existing translations, delete outdated translations but that's another story.
