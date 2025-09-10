/////////////////////////////////////////////////////////////////////////////
//
// The Braid Programming Language - the variable and stack frame classes
//
//
// Copyright (c) 2023 Bruce Payette (see LICENCE file) 
//
////////////////////////////////////////////////////////////////////////////

using System;
using System.Runtime.CompilerServices;
using System.Linq;
using System.Linq.Expressions;
using System.Collections;
using System.Collections.Specialized;
using System.Text;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Management.Automation;
using System.Reflection;
using System.Reflection.Emit;
using Microsoft.CSharp.RuntimeBinder;

namespace BraidLang
{
    ///////////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Utilities for dynamic type operations.
    /// </summary>
    public static class DynamicUtils
    {
        public static bool GetProperty(bool quiet, object obj, string name, out object result, ref CallSite<Func<CallSite, object, object>> callSite)
        {
            result = null;
            if (obj == null)
            {
                return false;
            }

            // System.Dynamic.IDynamicMetaObjectProvider idmop = obj as System.Dynamic.IDynamicMetaObjectProvider;
            // idmop.GetMetaObject(idmop);
            bool objIsType = obj is Type;
            var otype = objIsType ? (Type)obj : obj.GetType();

            if (!objIsType)
            {
                // Handle Instance members using CallSites
                if (callSite == null)
                {
                    callSite = GetSite(otype, obj, name);
                }

                if (callSite != null)
                {
                    result = callSite.Target(callSite, obj);
                    return true;
                }
            }
            callSite = null;

            // Fall through to reflection for fields and static properties
            var pinfo = otype.GetProperty(name, BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance | BindingFlags.IgnoreCase);
            if (pinfo != null)
            {
                result = pinfo.GetValue(obj);
                return true;
            }

            var finfo = otype.GetField(name, BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance | BindingFlags.IgnoreCase);
            if (finfo != null)
            {
                result = finfo.GetValue(obj);
                return true;
            }

            return false;
        }

        static ConcurrentDictionary<string, CallSite<Func<CallSite, object, object>>> _getterSites =
            new ConcurrentDictionary<string, CallSite<Func<CallSite, object, object>>>(StringComparer.OrdinalIgnoreCase);
        static CallSite<Func<CallSite, object, object>> GetSite(Type otype, object dyn, string propName)
        {
            string key = otype.FullName + "|" + propName;
            if (_getterSites.TryGetValue(key, out CallSite<Func<CallSite, object, object>> getterSite))
            {
                return getterSite;
            }

            var pinfo = otype.GetProperty(propName, BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance | BindingFlags.IgnoreCase);
            if (pinfo == null)
            {
                return null;
            }

            propName = pinfo.Name;
            key = otype.FullName + "|" + propName;

            getterSite =
                CallSite<Func<CallSite, object, object>>
                .Create(
                  Microsoft.CSharp.RuntimeBinder.Binder.GetMember(
                      CSharpBinderFlags.None,
                      propName,
                        otype,
                        new CSharpArgumentInfo[] {
                            CSharpArgumentInfo.Create(
                                CSharpArgumentInfoFlags.None, null)}));
            _getterSites[key] = getterSite;
            return getterSite;
        }

        public static bool SetProperty(object obj, string name, dynamic val, out object result, ref Delegate lambda)
        {
            result = null;
            bool isType = obj is Type;
            Type otype = isType ? (Type)obj : obj.GetType();
            lambda = null;
            PropertyInfo prop = null;

            if (!isType)
            {
                try
                {
                    string key = otype.FullName + "|" + name;
                    //if (lambda == null && !_lambdas.TryGetValue(key, out lambda))
                    if (!_pinfos.TryGetValue(key, out prop))
                    {
                        prop = otype.GetProperty(name, BindingFlags.IgnoreCase | BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static);

                        if (prop == null)
                        {
                            return false;
                        }

                        _pinfos[key] = prop;

                        /*
                        name = prop.Name;
                        var param1 = Expression.Parameter(obj.GetType(), "obj");
                        var param2 = Expression.Parameter(prop.PropertyType, "val");
                        var pexpr = Expression.PropertyOrField(param1, name);
                        var expr2 = Expression.Assign(pexpr, param2);
                        lambda = Expression.Lambda(expr2, param1, param2).Compile();
                        _lambdas[key] = lambda;
                        */
                    }

                    prop.SetValue(obj, val);
                    result = val;
                    //mresult = lambda.DynamicInvoke(obj, val);
                    return true;
                }
                catch
                {
                    return false;
                }
            }
            else
            {
                // Use reflection for static members...
                prop = otype.GetProperty(name, BindingFlags.IgnoreCase | BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static);

                if (prop == null)
                {
                    return false;
                }

                name = prop.Name;
                prop.SetValue(null, val);
                result = val;
                return true;
            }
        }

        ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

        static ConcurrentDictionary<string, Delegate> _lambdas =
            new ConcurrentDictionary<string, Delegate>(StringComparer.OrdinalIgnoreCase);
        static ConcurrentDictionary<string, PropertyInfo> _pinfos =
            new ConcurrentDictionary<string, PropertyInfo>(StringComparer.OrdinalIgnoreCase);

        static ConcurrentDictionary<string, MethodInfo> _methodInfoCache =
            new ConcurrentDictionary<string, MethodInfo>(StringComparer.OrdinalIgnoreCase);

        static ConcurrentDictionary<string, Delegate> _delegateCache =
            new ConcurrentDictionary<string, Delegate>(StringComparer.OrdinalIgnoreCase);

        /// <summary>
        /// Dynamically invoke a method.
        /// </summary>
        /// <param name="quiet">
        /// When this is true, if the method is not found, null is silently returned
        /// otherwise a method lookup exception will be returned.
        /// </param>
        /// <param name="obj">The object on which to look for the method</param>
        /// <param name="method">The name of the method to invoke</param>
        /// <param name="argArray">Arguments to pass to the method</param>
        /// <param name="delToCall">
        /// An optional delegate to use for calling the method.
        /// </param>
        /// <returns></returns>
        public static object InvokeMethod(bool quiet, dynamic obj, string method, object[] argArray, ref Delegate delToCall)
        {
            bool argWasType = false;

            object res;

            Type otype;
            if (obj is Type type)
            {
                otype = type;
                argWasType = true;
            }
            else
            {
                otype = obj.GetType();
                argWasType = false;
            }

            int arity = argArray.Length;

            // Creating an expression for the method call and specifying its parameter.
            //
            object[] argArray2 = null;
            string cacheKey = null;

            if (delToCall == null)
            {
                cacheKey = otype.FullName + "|" + method + "|" + arity;
                _delegateCache.TryGetValue(cacheKey, out delToCall);
            }

            if (delToCall != null)
            {
                if (!argWasType)
                {
                    argArray2 = new object[argArray.Length + 1];
                    argArray2[0] = obj;
                    argArray.CopyTo(argArray2, 1);
                }
                else
                {
                    argArray2 = argArray;
                }

                return delToCall.DynamicInvoke(argArray2);
            }

            MethodInfo methodInfo = null;
            if (_methodInfoCache.TryGetValue(cacheKey, out methodInfo))
            {
                ParameterInfo[] parameters = methodInfo.GetParameters();
                var parameterExprs = new List<ParameterExpression>();
                parameterExprs.AddRange(parameters.Select(parameter => Expression.Parameter(parameter.ParameterType)));

                // var paramExpressions = parameterExprs.Select(p => Expression.Convert(p, typeof(object)));
                MethodCallExpression methodCall;

                if (argWasType)
                {
                    methodCall = Expression.Call(
                        methodInfo,
                        parameterExprs);
                }
                else
                {
                    var objExpr = Expression.Parameter(obj.GetType());
                    methodCall = Expression.Call(
                        objExpr,
                        methodInfo,
                        parameterExprs
                    );

                    parameterExprs.Insert(0, objExpr);
                }

                // The following statement first creates an expression tree,
                // then compiles it, and then runs it.
                var methodLambda = Expression.Lambda(
                    methodCall,
                    parameterExprs
                );

                var lambdaDelegate = methodLambda.Compile();
                _delegateCache[cacheKey] = lambdaDelegate;

                if (argWasType)
                {
                    argArray2 = argArray;
                }
                else
                {
                    argArray2 = new object[argArray.Length + 1];
                    argArray2[0] = obj;
                    argArray.CopyTo(argArray2, 1);
                }

                return lambdaDelegate.DynamicInvoke(argArray2);
            }

            // Find the appropriate method...
            try
            {
                methodInfo = otype.GetMethod(method,
                                    BindingFlags.Public
                                    | BindingFlags.Static
                                    | BindingFlags.Instance
                                    | BindingFlags.IgnoreCase,
                                    null,
                                    argArray.Select(it => it.GetType()).ToArray(),
                                    argArray.Select(it => new ParameterModifier()).ToArray());
            }
            catch
            {
                string types = string.Join(", ", argArray.Select(it => it == null ? "null" : it.GetType().ToString()));
                // Ignore all exceptions and report that the method can't be found.
                Braid.BraidRuntimeException($"method '{method}' not found on object of type '{otype}'; arg values were: [{types}] ");
            }

            if (methodInfo == null)
            {
                if (quiet)
                {
                    return null;
                }

                Braid.BraidRuntimeException($"method '.{method}' not found on object of type '^{otype}'");
            }

            _methodInfoCache[cacheKey] = methodInfo;

            if (argWasType)
            {
                res = methodInfo.Invoke(null, argArray);
            }
            else
            {
                res = methodInfo.Invoke(obj, argArray);
            }

            return res;
        }
    }

    //////////////////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Handles dynamic type generation (deftype) including holding the type alias table.
    /// </summary>
    public static class BraidTypeBuilder
    {
        /// <summary>
        /// Routine to create a new .NET class for Braid
        /// </summary>
        /// <param name="className">Name of the class to create</param>
        /// <param name="baseClass">The base class to use for the new class</param>
        /// <param name="properties">The list of properties to define</param>
        /// <param name="methods">The list of methods to associate with this type.</param>
        /// <returns></returns>
        public static Type NewType(string className, Type baseClass, Type[] interfaces,
            OrderedDictionary properties, List<Tuple<Symbol,bool,UserFunction>> methods, bool isInterface = false)
        {
            var asmName = new AssemblyName(className);
            var assemblyBuilder = System.Reflection.Emit.AssemblyBuilder.DefineDynamicAssembly(asmName, AssemblyBuilderAccess.Run);

            var moduleBuilder = assemblyBuilder.DefineDynamicModule(className + "_MainModule");

            baseClass = (baseClass == null && !isInterface) ? typeof(BraidTypeBase) : baseClass;

            TypeAttributes typeAttrs;
            if (isInterface)
            {
                typeAttrs = TypeAttributes.Public | TypeAttributes.Interface | TypeAttributes.Abstract;
            }
            else
            {
                typeAttrs = TypeAttributes.Public | TypeAttributes.Class;
            }

            string typeNameToUse = className;
            if (!className.Contains("."))
            {
                typeNameToUse = "BraidLang.DynamicType." + className;
            }

            var classToBuild = moduleBuilder.DefineType(typeNameToUse, typeAttrs, baseClass);

            // Put the type builder in the type alias for now so recursive type definitions work.
            // We'll replace it with the reified type at the end.
            Braid.CallStack.SetTypeAlias(className, classToBuild);

            if (interfaces != null)
            {
                foreach (var iif in interfaces)
                {
                    classToBuild.AddInterfaceImplementation(iif);
                }
            }
            
            UInt16 index = 0;
            Type[] constructorArgs = new Type[properties.Count];
            FieldInfo[] fields = new FieldInfo[properties.Count];
            foreach (DictionaryEntry pair in properties)
            {
                Type memberType = typeof(object);
                if (pair.Value is Type t)
                {
                    memberType = t;
                }
                else if (pair.Value is TypeLiteral tlit)
                {
                    // Allow circular type references
                    if (tlit.TypeName.Equals(className, StringComparison.OrdinalIgnoreCase))
                    {
                        memberType = classToBuild;
                    }
                    else
                    {
                        memberType = tlit.Value as Type;
                    }
                }

                fields[index] = addPropertyToClass(classToBuild, pair.Key.ToString(), memberType, isInterface);
                constructorArgs[index] = memberType;
                index++;
            }

            if (!isInterface)
            {
                if (properties.Count > 0)
                {
                    // If there are properties, then also add the default parameter constructor
                    classToBuild.DefineDefaultConstructor(
                        MethodAttributes.Public | MethodAttributes.SpecialName | MethodAttributes.RTSpecialName);
                }

                // Add the non-default constructor which initializes all of the members of the type
                ConstructorBuilder myConstructorBuilder =
                    classToBuild.DefineConstructor(MethodAttributes.Public,
                          CallingConventions.Standard, constructorArgs);

                var myConstructorIL = myConstructorBuilder.GetILGenerator();

                // If there is a base class and if so, invoke its default constructor.
                var baseCtor = (baseClass == null) ? null :
                    baseClass.GetConstructor(BindingFlags.NonPublic | BindingFlags.Public | BindingFlags.Instance, null, new Type[0], null);
                if (baseCtor != null)
                {
                    myConstructorIL.Emit(OpCodes.Ldarg_0);
                    myConstructorIL.Emit(OpCodes.Call, baseCtor);
                }

                // Generate IL for the method.The constructor stores its argument in the private field.
                index = 0;
                while (index < fields.Length)
                {
                    myConstructorIL.Emit(OpCodes.Ldarg_0);
                    myConstructorIL.Emit(OpCodes.Ldarg, index + 1);
                    myConstructorIL.Emit(OpCodes.Stfld, fields[index]);
                    index++;
                }

                // Finally add the method return.
                myConstructorIL.Emit(OpCodes.Ret);
            }

            if (methods != null)
            {
                foreach (Tuple<Symbol, bool, UserFunction> nvpair in methods)
                {
                    if (nvpair.Item1 != Symbol.sym_new)
                    {
                        addMethodToClass(classToBuild, methodName: nvpair.Item1.Value, lambda: nvpair.Item3, isInterface, isStatic: nvpair.Item2 );
                    }   
                }
            }

            // Finally reify the type
            Type type = classToBuild.CreateType();

            // Replace the typebuilder in the type alias table with the actual type
            Braid.CallStack.SetTypeAlias(className, type);

            // Constructors defined in braid (i.e. method new) use the Braid extension mechanism.
            // This should be replaced by real constructors eventually.
            if (methods != null)
            {
                foreach (Tuple<Symbol, bool, UserFunction> nvpair in methods)
                {
                    if (nvpair.Item1 == Symbol.sym_new)
                    {
                        AddMethodToMap(type, nvpair.Item1, nvpair.Item3);
                    }
                }
            }

            return type;
        }

        /// <summary>
        /// Sets up association between types and extension methods.
        /// </summary>
        /// <param name="type">The type to associate a method with</param>
        /// <param name="methods">A dictionary of name/lambda pairs to associate</param>
        static void AddMethodToMap(Type type, Symbol name, UserFunction body)
        {
            TypeMethodMap.AddOrUpdate(type,
                (t) =>
                {
                    var d = new Dictionary<Symbol, UserFunction>
                    {
                        [name] = body
                    };
                    return d;
                },
                (t, d) =>
                {
                    d[name] = body;
                    return d;
                });
        }

        /// <summary>
        /// Gets the named method for the specified type
        /// </summary>
        /// <param name="type">The type to look at</param>
        /// <param name="name">The name of the method to retrieve.</param>
        /// <returns></returns>
        internal static UserFunction GetMethodFromMap(Type type, Symbol name)
        {
            while (type != null && type != typeof(object))
            {
                Dictionary<Symbol, UserFunction> methods;
                if (TypeMethodMap.TryGetValue(type, out methods))
                {
                    if (methods.TryGetValue(name, out UserFunction mbody))
                    {
                        return mbody;
                    }
                }
                type = type.BaseType;
            }
            return null;
        }

        // The method map for binding methods to types.
        internal static ConcurrentDictionary<Type, Dictionary<Symbol, UserFunction>> TypeMethodMap =
            new ConcurrentDictionary<Type, Dictionary<Symbol, UserFunction>>();

        // BUGBUGBUG - this should be thread-safe...
        internal static List<UserFunction> MethodDispatchTable = new List<UserFunction>();

        public static Vector getExtensionMethods(Type type)
        {
            Vector result = new Vector();
            Dictionary<Symbol, UserFunction> entry;

            if (TypeMethodMap.TryGetValue(type, out entry))
            {
                foreach (var m in entry)
                {
                    result.Add("X " + m.Key.Value + m.Value.Signature);
                }
            }

            return result;
        }

        /// <summary>
        /// Routine to add a method to a constructed type. This routine generates a method
        /// that marshals its arguments into an array then passes the array to MethodDispatchTable
        /// index along with the argument array to another method that does the actual
        /// lambda dispatch.
        /// </summary>
        /// <param name="typeBuilder"></param>
        /// <param name="methodName"></param>   
        /// <param name="lambda"></param>
        static void addMethodToClass(TypeBuilder typeBuilder, string methodName, UserFunction lambda, bool isInterface, bool isStatic)
        {
            Vector args = lambda.Arguments;

            Symbol first_argument = null;

            if (args.Count > 0)
            {
                if (args[0] is MatchElementBase ve)
                {
                    first_argument = ve.Variable;
                }
                else if (args[0] is Symbol sym)
                {
                    first_argument = sym;
                }
            }

            if (! isStatic && (first_argument == null || first_argument != Symbol.sym_this))
            {
                string notmsg = args.Count > 0 ? $", not '{args[0]}'" : "";
                Braid.BraidRuntimeException(
                    $"Invalid parameter specification for method '{methodName}'. The first parameter to " +
                    $"a method must be 'this'{notmsg}.");
            }

            Type returnType = typeof(object);
            if (lambda.ReturnType != null)
            {
                // For self-referential type, if the method's return type name matches the
                // typename of the class being constructed use the typebuilder directly instead
                // of trying to look up the type.
                if (string.Equals(lambda.ReturnType.TypeName, typeBuilder.FullName, StringComparison.OrdinalIgnoreCase))
                {
                    returnType = typeBuilder;
                }
                else
                {
                    returnType = lambda.ReturnType.Value as Type;
                }
            }

            Type[] argTypes;
            int start;
            int offset;
            if (isStatic)
            {
                start = 0;
                offset = 0;
                argTypes = (args.Count > 0) ? (new Type[args.Count]) : Type.EmptyTypes;
            }
            else
            {
                start = 1;
                offset = 1;
                argTypes = (args.Count > 0) ? (new Type[args.Count - 1]) : Type.EmptyTypes;
            }

            // Get the parameter types into an array
            if (args != null && args.Count > 0)
            {
                for (int i = start; i < args.Count; i++)
                {
                    if (args[i] is TypeElement te)
                    {
                        // again handle self-referential types.
                        if (string.Equals(te.Tlit.TypeName, typeBuilder.Name, StringComparison.OrdinalIgnoreCase))
                        {
                            argTypes[i - offset] = typeBuilder.AsType();
                        }
                        else
                        {
                            argTypes[i - offset] = te.Tlit.Type;
                        }
                    }
                    else if (args[i] is s_Expr sexpr)
                    {
                        if (sexpr.Car is TypeLiteral tlit)
                        {
                            if (string.Equals(tlit.TypeName, typeBuilder.Name, StringComparison.OrdinalIgnoreCase))
                            {
                                argTypes[i - offset] = typeBuilder.AsType();
                            }
                            else
                            {
                                argTypes[i - offset] = tlit.Value as Type;
                            }
                        }
                        else
                        {
                            Braid.BraidRuntimeException($"Method '{methodName}'; parameter '{sexpr.Car}': " +
                                "method parameter initializers are not supported.");
                        }
                    }

                    if (argTypes[i - offset] == null)
                    {
                        argTypes[i - offset] = typeof(object);
                    }
                }
            }

            // BUGBUGBUG - still need to handle optional parameters, varargs, etc.

            MethodAttributes attrs = MethodAttributes.Public;
            if (isStatic)
            {
                attrs |=  MethodAttributes.Static;
            }
            else
            {
                attrs |=  MethodAttributes.Virtual | MethodAttributes.HideBySig;
            }

            if (isInterface)
            {
                attrs |= MethodAttributes.Abstract;
            }

            MethodBuilder methodBldr = typeBuilder.DefineMethod(
                methodName,
                attrs,
                isStatic ? CallingConventions.Standard : CallingConventions.HasThis,
                returnType,
                argTypes);

            ILGenerator mgen = methodBldr.GetILGenerator();

            // gen code to build a local array to hold the actual arguments
            LocalBuilder arr = mgen.DeclareLocal(typeof(object));
            mgen.Emit(OpCodes.Ldc_I4, args.Count);
            mgen.Emit(OpCodes.Newarr, typeof(object));
            mgen.Emit(OpCodes.Stloc, arr);

            // now add code to copy the method arguments into the array 
            for (var i = 0; i < args.Count; i++)
            {
                mgen.Emit(OpCodes.Ldloc, arr);
                mgen.Emit(OpCodes.Ldc_I4_S, i);
                mgen.Emit(OpCodes.Ldarg, i);
                // need to box value types before they can go into the array.
                if (i >= offset && argTypes[i - offset].IsValueType)
                {
                    mgen.Emit(OpCodes.Box, argTypes[i - offset]);
                }

                mgen.Emit(OpCodes.Stelem_Ref);
            }

            // Add the Braid lambda implementing the method body to the method dispatch table.
            // The generated method will use the index of the method body to find
            // the Braid code at runtime.
            lambda.Name = methodName;
            MethodDispatchTable.Add(lambda);

            // Add the code to call the dispatcher function. The dispatcher function
            // arguments are the index of the method lambda in the dispatch index
            // and the argument array
            mgen.Emit(OpCodes.Ldc_I4, MethodDispatchTable.Count-1); // dispatch index
            mgen.Emit(OpCodes.Ldloc, arr);                          // the argument array
            mgen.Emit(OpCodes.Call, methodDispatchHelper);

            if (returnType == typeof(void))
            {
                // If the return type is void, drop the returned value from the stack
                mgen.Emit(OpCodes.Pop);
            }
            else if (returnType.IsValueType)
            {
                // If the return type is a value type, unbox it.
                mgen.Emit(OpCodes.Unbox_Any, returnType);
            }

            mgen.Emit(OpCodes.Ret);
        }

        // The dispatch helper method we'll use to call the real method implementation.
        static MethodInfo methodDispatchHelper = typeof(BraidTypeBuilder).GetMethod("MethodDispatchHelper");

        //////////////////////////////////////////////////////////////////////////////////////
        /// <summary>
        /// Helper method for dispatching user-defined methods. This is not referenced directly
        /// in code but is only accessed through reflection.
        /// </summary>
        /// <param name="methodIndex">Index in the method table for this methods body</param>
        /// <param name="funcArgs">The arguments to the Braid function.</param>
        /// <returns></returns>
        public static object MethodDispatchHelper(int methodIndex, object[] funcArgs)
        {
            var methodBody = BraidTypeBuilder.MethodDispatchTable[methodIndex];

            if (methodBody == null)
            {
                Braid.BraidRuntimeException($"In MethodDispatchHelper; no method at " +
                    $"index {methodIndex} was found.");
            }

            if (methodBody.Arguments.Count != funcArgs.Length)
            {
                Braid.BraidRuntimeException(
                    $"In MethodDispatchHelper invoking method '{methodBody}'- the arity " +
                    $"of funcArgs ({funcArgs.Length})  doesn't match the arity of the lambda ({methodBody.Arguments.Count}).");
            }

            object result = methodBody.Invoke(new Vector(funcArgs), null);
            return result;
        }

        /// <summary>
        /// Method to add a property to a constructed type.
        /// </summary>
        /// <param name="typeBuilder"></param>
        /// <param name="propertyName"></param>
        /// <param name="propertyType"></param>
        /// <returns></returns>
        static FieldBuilder addPropertyToClass(TypeBuilder typeBuilder, string propertyName, Type propertyType, bool isInterface)
        {
            FieldBuilder fieldBuilder = null;

            bool isStatic = false;
            // static membe names start with '/'.
            if (propertyName[0] == '/')
            {
                isStatic = true;
                propertyName = propertyName.Substring(1);
            }

            if (!isInterface)
            {
                var fattrs = FieldAttributes.Private;
                if (isStatic)
                {
                    fattrs |= FieldAttributes.Static;
                }

                fieldBuilder = typeBuilder.DefineField("__" + propertyName, propertyType, fattrs);
            }

            PropertyBuilder propertyBuilder = typeBuilder.DefineProperty(propertyName, PropertyAttributes.HasDefault, propertyType, null);

            MethodAttributes attrs = MethodAttributes.Public | MethodAttributes.SpecialName | MethodAttributes.HideBySig;
            if (isInterface)
            {
                attrs |= MethodAttributes.Abstract | MethodAttributes.Virtual;
            }
            else if (isStatic)
            {
                attrs |= MethodAttributes.Static;
            }
            else
            {
                attrs |= MethodAttributes.Virtual;
            }

            MethodBuilder accesorMethodBuilder = typeBuilder.DefineMethod(
                "get_" + propertyName,
                attrs,
                propertyType,
                Type.EmptyTypes);

            ILGenerator getIl = accesorMethodBuilder.GetILGenerator();

            if (!isInterface)
            {
                if (isStatic)
                {
                    getIl.Emit(OpCodes.Ldsfld, fieldBuilder);
                }
                else
                {
                    getIl.Emit(OpCodes.Ldarg_0);
                    getIl.Emit(OpCodes.Ldfld, fieldBuilder);
                }
            }

            getIl.Emit(OpCodes.Ret);

            MethodBuilder setPropMthdBldr = typeBuilder.DefineMethod("set_" + propertyName,
                  attrs, null, new[] { propertyType });

            ILGenerator setIl = setPropMthdBldr.GetILGenerator();

            Label modifyProperty = setIl.DefineLabel();
            Label exitSet = setIl.DefineLabel();

            setIl.MarkLabel(modifyProperty);

            if (isStatic)
            {
                setIl.Emit(OpCodes.Ldarg_0);
                setIl.Emit(OpCodes.Stsfld, fieldBuilder);
            }
            else
            {
                setIl.Emit(OpCodes.Ldarg_0);
                setIl.Emit(OpCodes.Ldarg_1);

                if (!isInterface)
                {
                    setIl.Emit(OpCodes.Stfld, fieldBuilder);
                }
            }

            setIl.Emit(OpCodes.Nop);
            setIl.MarkLabel(exitSet);
            setIl.Emit(OpCodes.Ret);

            propertyBuilder.SetGetMethod(accesorMethodBuilder);
            propertyBuilder.SetSetMethod(setPropMthdBldr);

            // Return the field instead of the property because it will be used
            // in the constructor.
            return fieldBuilder;
        }

        public static Type MakeFuncType(Type rettype)
        {
            return typeof(System.Func<>).MakeGenericType(rettype);
        }

        public static Type MakeFuncType(Type rettype, Type arg1)
        {
            return typeof(System.Func<,>).MakeGenericType(arg1, rettype);
        }

        public static Type MakeFuncType(Type rettype, Type arg1, Type arg2)
        {
            return typeof(System.Func<,,>).MakeGenericType(arg1, arg2, rettype);
        }

        public static Type MakeFuncType(Type rettype, Type arg1, Type arg2, Type arg3)
        {
            return typeof(System.Func<,,,>).MakeGenericType(arg1, arg2, arg3, rettype);
        }

        public static Type MakeFuncType(Type rettype, Type arg1, Type arg2, Type arg3, Type arg4)
        {
            return typeof(System.Func<,,,,>).MakeGenericType(arg1, arg2, arg3, arg4, rettype);
        }

        public static Type MakeFuncType(Type rettype, Type arg1, Type arg2, Type arg3, Type arg4, Type arg5)
        {
            return typeof(System.Func<,,,,,>).MakeGenericType(arg1, arg2, arg3, arg4, arg5, rettype);
        }
    }
   
    //////////////////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Used as the default base class for all types defined in the Braid session using defrecord and deftype.
    /// Other types can be used as base classes but functionality will vary.
    /// </summary>
    public class BraidTypeBase : IEquatable<object>, IComparable
    {
        public override string ToString()
        {
            // See if there is an overload of ToString() as a Braid dynamic method
            Callable methodBody = BraidTypeBuilder.GetMethodFromMap(this.GetType(), Symbol.sym_tostring);
            if (methodBody != null)
            {
                object result = methodBody.Invoke(new Vector { this });
                if (result == null)
                    return string.Empty;
                else
                    return result.ToString();
            }

            // Otherwise build a string up out of the members
            StringBuilder sb = new StringBuilder("{");
            bool first = true;
            foreach (var p in this.GetType().GetProperties(BindingFlags.Public|BindingFlags.Instance|BindingFlags.FlattenHierarchy))
            {
                string name = p.Name;
                object val = p.GetValue(this);
                if (first)
                {
                    first = false;
                }
                else
                {
                    sb.Append(", ");
                }

                sb.Append('"');
                sb.Append(name);
                sb.Append("\" : ");
                sb.Append(Utils.ToSourceString(val));
            }

            sb.Append("}");
            return sb.ToString();
        }

        // Two Braid objects are equal if they have the same members and the members have the same values.
        public override bool Equals(object obj)
        {
            // See if there is an overload of Equal() as a Braid dynamic method
            Callable methodBody = BraidTypeBuilder.GetMethodFromMap(this.GetType(), Symbol.sym_equals);
            if (methodBody != null)
            {
                return Braid.IsTrue(methodBody.Invoke(new Vector { this, obj }));
            }

            var objProps = obj.GetType().GetProperties(
                BindingFlags.Public | BindingFlags.Instance | BindingFlags.FlattenHierarchy).OrderBy(prop => prop.Name).ToArray();
            var thisProps = this.GetType().GetProperties(
                BindingFlags.Public | BindingFlags.Instance | BindingFlags.FlattenHierarchy).OrderBy(prop => prop.Name).ToArray();

            if (objProps.Length != thisProps.Length)
            {
                return false;
            }

            if (! objProps.Select(prop => prop.Name).SequenceEqual(thisProps.Select(prop => prop.Name)))
            {
                return false;
            }

            for (var i =0; i < objProps.Length; i++)
            {
                if (thisProps[i].GetValue(this) != objProps[i].GetValue(obj))
                {
                    return false;
                }
            }

            return true;
        }

        public int CompareTo(object obj)
        {
            // See if there is an overload of CompareTo() as a Braid dynamic method
            Callable methodBody = BraidTypeBuilder.GetMethodFromMap(this.GetType(), Symbol.sym_compareto);
            if (methodBody != null)
            {
                return Braid.ConvertToHelper<int>(methodBody.Invoke(new Vector { this, obj }));
            }

            return (int) LanguagePrimitives.Compare(this, obj, true);
        }
        
        public override int GetHashCode()
        {
            // See if there is an overload of CompareTo() as a Braid dynamic method
            Callable methodBody = BraidTypeBuilder.GetMethodFromMap(this.GetType(), Symbol.sym_gethashcode);
            if (methodBody != null)
            {
                return Braid.ConvertToHelper<int>(methodBody.Invoke(new Vector { this }));
            }
            
            return base.GetHashCode();
        }
    }
}
